import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/tables/unified_sync_tables.dart';
import 'sync_contract_v3.dart';

class InboundSyncChange {
  const InboundSyncChange({
    required this.serverSequence,
    required this.changeId,
    required this.entityType,
    required this.entityId,
    required this.entityUuid,
    required this.operation,
    required this.revision,
    required this.occurredAt,
    required this.payload,
  });

  final int serverSequence;
  final String changeId;
  final String entityType;
  final String entityId;
  final String entityUuid;
  final String operation;
  final int revision;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
}

class UnifiedSyncQueueService {
  UnifiedSyncQueueService._();

  static Future<List<Map<String, Object?>>> pendingOutbox(
    DatabaseExecutor db, {
    int limit = SyncContractV3.pushMaxChanges,
  }) async {
    SyncContractV3.requirePushBatchSize(limit);
    final now = DateTime.now().toUtc().toIso8601String();
    return (await db.query(
      UnifiedSyncTables.outbox,
      where:
          "state='PENDING' AND (next_attempt_at IS NULL OR next_attempt_at<=?)",
      whereArgs: [now],
      orderBy: 'created_at ASC,outbox_id ASC',
      limit: limit,
    ))
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  static Future<void> markSending(DatabaseExecutor db, String outboxId) async {
    final changed = await db.update(
      UnifiedSyncTables.outbox,
      {'state': 'SENDING', 'updated_at': _now()},
      where: "outbox_id=? AND state='PENDING'",
      whereArgs: [outboxId],
    );
    if (changed != 1) throw StateError('SYNC_OUTBOX_INVALID_TRANSITION');
  }

  static Future<void> markAcknowledged(
    DatabaseExecutor db,
    String outboxId, {
    required int serverSequence,
  }) async {
    if (serverSequence < 1) throw ArgumentError.value(serverSequence);
    final changed = await db.update(
      UnifiedSyncTables.outbox,
      {
        'state': 'ACKNOWLEDGED',
        'server_sequence': serverSequence,
        'last_error': null,
        'next_attempt_at': null,
        'updated_at': _now(),
      },
      where: "outbox_id=? AND state='SENDING'",
      whereArgs: [outboxId],
    );
    if (changed != 1) throw StateError('SYNC_OUTBOX_INVALID_TRANSITION');
  }

  static Future<void> markConflict(
    DatabaseExecutor db,
    String outboxId, {
    required String conflictId,
  }) async {
    final changed = await db.update(
      UnifiedSyncTables.outbox,
      {
        'state': 'CONFLICT',
        'remote_conflict_id': conflictId,
        'updated_at': _now(),
      },
      where: "outbox_id=? AND state='SENDING'",
      whereArgs: [outboxId],
    );
    if (changed != 1) throw StateError('SYNC_OUTBOX_INVALID_TRANSITION');
  }

  static Future<void> returnToPending(
    DatabaseExecutor db,
    String outboxId, {
    required String error,
  }) async {
    final row = await db.query(
      UnifiedSyncTables.outbox,
      columns: ['attempt_count'],
      where: 'outbox_id=?',
      whereArgs: [outboxId],
      limit: 1,
    );
    if (row.isEmpty) throw StateError('SYNC_OUTBOX_NOT_FOUND');
    final attempts = ((row.single['attempt_count'] as num?)?.toInt() ?? 0) + 1;
    final exponent = attempts < 1 ? 1 : (attempts > 8 ? 8 : attempts);
    final seconds = 5 * (1 << (exponent - 1));
    final delaySeconds = seconds > 900 ? 900 : seconds;
    final next = DateTime.now().toUtc().add(Duration(seconds: delaySeconds));
    final changed = await db.update(
      UnifiedSyncTables.outbox,
      {
        'state': 'PENDING',
        'attempt_count': attempts,
        'last_error': error.length > 1000 ? error.substring(0, 1000) : error,
        'next_attempt_at': next.toIso8601String(),
        'updated_at': _now(),
      },
      where: "outbox_id=? AND state='SENDING'",
      whereArgs: [outboxId],
    );
    if (changed != 1) throw StateError('SYNC_OUTBOX_INVALID_TRANSITION');
  }

  static Future<void> resetInterruptedSending(DatabaseExecutor db) async {
    final now = _now();
    await db.rawUpdate(
      '''UPDATE ${UnifiedSyncTables.outbox}
      SET state='PENDING',attempt_count=attempt_count+1,
          last_error='Interrupted before server acknowledgement',
          next_attempt_at=?,updated_at=? WHERE state='SENDING' ''',
      [now, now],
    );
  }

  static Future<void> markRejected(
    DatabaseExecutor db,
    String outboxId, {
    required String error,
  }) async {
    final changed = await db.update(
      UnifiedSyncTables.outbox,
      {
        'state': 'REJECTED',
        'last_error': error.length > 1000 ? error.substring(0, 1000) : error,
        'next_attempt_at': null,
        'updated_at': _now(),
      },
      where: "outbox_id=? AND state='SENDING'",
      whereArgs: [outboxId],
    );
    if (changed != 1) throw StateError('SYNC_OUTBOX_INVALID_TRANSITION');
  }

  static Future<int> checkpointFor(
    DatabaseExecutor db,
    String organizationId,
  ) async {
    final rows = await db.query(
      UnifiedSyncTables.checkpoint,
      columns: ['last_server_sequence'],
      where: 'organization_id=?',
      whereArgs: [organizationId],
      limit: 1,
    );
    return rows.isEmpty
        ? 0
        : ((rows.single['last_server_sequence'] as num?)?.toInt() ?? 0);
  }

  static Future<int> applyInboundBatch(
    Database db, {
    required String organizationId,
    required List<InboundSyncChange> changes,
    required Future<void> Function(
      DatabaseExecutor transaction,
      InboundSyncChange change,
    ) apply,
  }) async {
    final org = organizationId.trim();
    if (org.isEmpty) {
      throw ArgumentError.value(organizationId, 'organizationId');
    }
    if (changes.length > SyncContractV3.pullMaxChanges) {
      throw RangeError.range(
        changes.length,
        0,
        SyncContractV3.pullMaxChanges,
        'changes.length',
      );
    }
    return db.transaction((txn) async {
      var checkpoint = await checkpointFor(txn, org);
      var previous = checkpoint;
      for (final change in changes) {
        _validateInbound(change);
        if (change.serverSequence <= previous) {
          final existing = await txn.query(
            UnifiedSyncTables.inbox,
            where: 'organization_id=? AND server_sequence=?',
            whereArgs: [org, change.serverSequence],
            limit: 1,
          );
          if (existing.isEmpty ||
              existing.single['change_id'] != change.changeId ||
              existing.single['payload_json'] != _canonical(change.payload) ||
              existing.single['state'] != 'APPLIED') {
            throw StateError('SYNC_INBOUND_REPLAY_MISMATCH');
          }
          continue;
        }
        final payloadJson = _canonical(change.payload);
        final inboxId = '$org:${change.serverSequence}';
        await txn.insert(UnifiedSyncTables.inbox, {
          'inbox_id': inboxId,
          'organization_id': org,
          'server_sequence': change.serverSequence,
          'change_id': change.changeId,
          'entity_type': change.entityType,
          'entity_id': change.entityId,
          'entity_uuid': change.entityUuid,
          'operation': change.operation,
          'revision': change.revision,
          'occurred_at': change.occurredAt.toUtc().toIso8601String(),
          'payload_json': payloadJson,
          'received_at': _now(),
          'state': 'RECEIVED',
        });
        await apply(txn, change);
        final applied = await txn.update(
          UnifiedSyncTables.inbox,
          {'state': 'APPLIED'},
          where: "inbox_id=? AND state='RECEIVED'",
          whereArgs: [inboxId],
        );
        if (applied != 1) throw StateError('SYNC_INBOX_INVALID_TRANSITION');
        previous = change.serverSequence;
      }
      if (previous > checkpoint) {
        await txn.rawInsert(
          '''INSERT INTO ${UnifiedSyncTables.checkpoint}
          (organization_id,last_server_sequence,updated_at) VALUES(?,?,?)
          ON CONFLICT(organization_id) DO UPDATE SET
            last_server_sequence=excluded.last_server_sequence,
            updated_at=excluded.updated_at''',
          [org, previous, _now()],
        );
        checkpoint = previous;
      }
      return checkpoint;
    });
  }

  static Future<UnifiedSyncQueueStats> queueStats(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''SELECT
      SUM(CASE WHEN state='PENDING' THEN 1 ELSE 0 END) AS pending,
      SUM(CASE WHEN state='SENDING' THEN 1 ELSE 0 END) AS sending,
      SUM(CASE WHEN state IN ('CONFLICT','REJECTED') THEN 1 ELSE 0 END) AS failed
      FROM ${UnifiedSyncTables.outbox}''');
    final row = rows.isEmpty ? const <String, Object?>{} : rows.single;
    return UnifiedSyncQueueStats(
      pending: (row['pending'] as num?)?.toInt() ?? 0,
      sending: (row['sending'] as num?)?.toInt() ?? 0,
      failed: (row['failed'] as num?)?.toInt() ?? 0,
    );
  }

  static void _validateInbound(InboundSyncChange change) {
    if (change.serverSequence < 1) {
      throw ArgumentError.value(change.serverSequence, 'serverSequence');
    }
    if (change.changeId.trim().isEmpty ||
        change.entityType.trim().isEmpty ||
        change.entityId.trim().isEmpty ||
        change.entityUuid.trim().isEmpty) {
      throw const FormatException('Inbound sync identity is incomplete.');
    }
    if (change.operation != 'UPSERT' && change.operation != 'DELETE') {
      throw const FormatException('Inbound sync operation is invalid.');
    }
    if (change.revision < 1) {
      throw ArgumentError.value(change.revision, 'revision');
    }
  }

  static String _canonical(Object? value) {
    Object? normalize(Object? input) {
      if (input is Map) {
        final keys = input.keys.map((e) => e.toString()).toList()..sort();
        return <String, Object?>{
          for (final key in keys) key: normalize(input[key]),
        };
      }
      if (input is List) return input.map(normalize).toList(growable: false);
      return input;
    }

    return jsonEncode(normalize(value));
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
}

class UnifiedSyncQueueStats {
  const UnifiedSyncQueueStats(
      {required this.pending, required this.sending, required this.failed});
  final int pending;
  final int sending;
  final int failed;
  int get unsent => pending + sending;
}
