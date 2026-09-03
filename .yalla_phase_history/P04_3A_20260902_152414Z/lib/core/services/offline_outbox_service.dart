import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'db/tables/technical_tables.dart';

/// Durable local-first mutation queue.
///
/// P04.2 intentionally does not send anything over the network. It only makes
/// local commits durable and records a retry-safe envelope in the same SQLite
/// transaction. The transport/drain loop is introduced later in P04.
class OfflineOutboxService {
  OfflineOutboxService._();

  static const String channelSync = 'sync';

  static Future<bool> enqueue(
    DatabaseExecutor db, {
    required String channel,
    required String operation,
    required String entityType,
    required String entityId,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    final cleanKey = idempotencyKey.trim();
    if (cleanKey.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'must not be empty',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final id = '$entityType:$entityId:$cleanKey';

    final inserted = await db.insert(
      TechnicalTables.outboxTable,
      {
        'id': id,
        'channel': channel,
        'operation': operation.trim().toUpperCase(),
        'entity_type': entityType,
        'entity_id': entityId,
        'idempotency_key': cleanKey,
        'payload_json': jsonEncode(payload),
        'created_at': now,
        'updated_at': now,
        'status': 'pending',
        'sent': 0,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return inserted != 0;
  }

  static Future<List<Map<String, dynamic>>> ready({
    required DatabaseExecutor db,
    int limit = 50,
    DateTime? now,
  }) {
    final at = (now ?? DateTime.now()).toUtc().toIso8601String();
    return db.query(
      TechnicalTables.outboxTable,
      where: "sent = 0 AND status IN ('pending','failed') "
          'AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
      whereArgs: [at],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  static Future<int> pendingCount(DatabaseExecutor db) async {
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM ${TechnicalTables.outboxTable} "
      "WHERE sent = 0 AND status IN ('pending','failed')",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> markSending(
    DatabaseExecutor db,
    String messageId,
  ) {
    return _setStatus(
      db,
      messageId,
      status: 'sending',
      clearError: false,
      nextAttemptAt: null,
    );
  }

  static Future<void> markSent(
    DatabaseExecutor db,
    String messageId,
  ) async {
    await db.update(
      TechnicalTables.outboxTable,
      {
        'status': 'sent',
        'sent': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
        'next_attempt_at': null,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  static Future<void> markFailed(
    DatabaseExecutor db,
    String messageId, {
    required String error,
    DateTime? now,
  }) async {
    final rows = await db.query(
      TechnicalTables.outboxTable,
      columns: ['attempt_count'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final attempts = ((rows.first['attempt_count'] as num?)?.toInt() ?? 0) + 1;
    final base = (now ?? DateTime.now()).toUtc();

    // Bounded exponential backoff: 5s, 10s, 20s ... max 15 minutes.
    final exponent = attempts < 1 ? 1 : (attempts > 8 ? 8 : attempts);
    final seconds = 5 * (1 << (exponent - 1));
    final delaySeconds = seconds > 900 ? 900 : seconds;
    final next = base.add(Duration(seconds: delaySeconds));

    await db.update(
      TechnicalTables.outboxTable,
      {
        'status': 'failed',
        'sent': 0,
        'attempt_count': attempts,
        'last_error': error.length > 1000 ? error.substring(0, 1000) : error,
        'next_attempt_at': next.toIso8601String(),
        'updated_at': base.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  static Future<void> resetInterruptedSending(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      TechnicalTables.outboxTable,
      {
        'status': 'failed',
        'sent': 0,
        'last_error': 'Interrupted before acknowledgement',
        'next_attempt_at': now,
        'updated_at': now,
      },
      where: "status = 'sending' AND sent = 0",
    );
  }

  static Future<void> _setStatus(
    DatabaseExecutor db,
    String messageId, {
    required String status,
    required bool clearError,
    required String? nextAttemptAt,
  }) async {
    final values = <String, Object?>{
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'next_attempt_at': nextAttemptAt,
    };
    if (clearError) values['last_error'] = null;

    await db.update(
      TechnicalTables.outboxTable,
      values,
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }
}
