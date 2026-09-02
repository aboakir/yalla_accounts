// 📁 lib/core/services/db/tables/technical_tables.dart
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database_constants.dart';

class TechnicalTables {
  static const String outboxTable = 'outbox_messages';

  // 🔄 إنشاء الجداول الفنية
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createDomainEventsTable(db);
    await _createOutboxTable(db);
  }

  // 📨 جدول الأحداث
  static Future<void> _createDomainEventsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS domain_events(
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        processed INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _ensureDomainEventsIndexes(db);
  }

  static Future<void> _ensureDomainEventsIndexes(
    DatabaseExecutor db,
  ) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_domain_events_type '
      'ON domain_events(type);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_domain_events_created '
      'ON domain_events(created_at);',
    );
  }

  // 📤 Durable local-first outbox.
  static Future<void> _createOutboxTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $outboxTable(
        id TEXT PRIMARY KEY,
        channel TEXT NOT NULL,
        operation TEXT NOT NULL DEFAULT 'UPSERT',
        entity_type TEXT,
        entity_id TEXT,
        idempotency_key TEXT,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        sent INTEGER NOT NULL DEFAULT 0,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT,
        last_error TEXT
      )
    ''');

    await ensureP04OutboxSchema(db);
  }

  /// P04.2 — upgrades the pre-existing technical outbox without deleting rows.
  ///
  /// This deliberately uses idempotent column checks instead of a destructive
  /// table rebuild, so an installation can safely move from the legacy
  /// `id/channel/payload/created/sent` layout to the durable local-first schema.
  static Future<void> ensureP04OutboxSchema(DatabaseExecutor db) async {
    await _ensureColumn(
      db,
      outboxTable,
      'operation',
      "TEXT NOT NULL DEFAULT 'UPSERT'",
    );
    await _ensureColumn(db, outboxTable, 'entity_type', 'TEXT');
    await _ensureColumn(db, outboxTable, 'entity_id', 'TEXT');
    await _ensureColumn(db, outboxTable, 'idempotency_key', 'TEXT');
    await _ensureColumn(db, outboxTable, 'updated_at', 'TEXT');
    await _ensureColumn(
      db,
      outboxTable,
      'status',
      "TEXT NOT NULL DEFAULT 'pending'",
    );
    await _ensureColumn(
      db,
      outboxTable,
      'attempt_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(db, outboxTable, 'next_attempt_at', 'TEXT');
    await _ensureColumn(db, outboxTable, 'last_error', 'TEXT');

    // Preserve the legacy `sent` column and project it into the new state.
    await db.execute('''
      UPDATE $outboxTable
      SET
        status = CASE
          WHEN sent = 1 THEN 'sent'
          WHEN status IS NULL OR TRIM(status) = '' THEN 'pending'
          ELSE status
        END,
        updated_at = CASE
          WHEN updated_at IS NULL OR TRIM(updated_at) = ''
          THEN created_at
          ELSE updated_at
        END,
        attempt_count = COALESCE(attempt_count, 0)
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_outbox_channel '
      'ON $outboxTable(channel);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_outbox_ready '
      'ON $outboxTable(status, next_attempt_at, created_at);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_outbox_entity '
      'ON $outboxTable(entity_type, entity_id);',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_outbox_idempotency '
      'ON $outboxTable(idempotency_key) '
      'WHERE idempotency_key IS NOT NULL;',
    );
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name']?.toString() == column);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }
  }

  // 🔄 ترقية الجداول
  static Future<void> onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 22) {
      await _createDomainEventsTable(db);
      await _createOutboxTable(db);
    } else {
      await ensureP04OutboxSchema(db);
    }
  }

  // 🎯 واجهات الاستخدام القديمة تبقى متوافقة.
  static Future<void> logDomainEvent(
    DatabaseExecutor db,
    String type,
    Map<String, dynamic> payload,
  ) async {
    await db.insert('domain_events', {
      'id': DatabaseConstants.newUuid(),
      'type': type,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'processed': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingDomainEvents(
    DatabaseExecutor db,
  ) async {
    return db.query(
      'domain_events',
      where: 'processed = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
      limit: 100,
    );
  }

  static Future<void> markDomainEventProcessed(
    DatabaseExecutor db,
    String eventId,
  ) async {
    await db.update(
      'domain_events',
      {'processed': 1},
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  static Future<void> addOutboxMessage(
    DatabaseExecutor db,
    String channel,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(outboxTable, {
      'id': DatabaseConstants.newUuid(),
      'channel': channel,
      'operation': 'UPSERT',
      'payload_json': jsonEncode(payload),
      'created_at': now,
      'updated_at': now,
      'status': 'pending',
      'sent': 0,
      'attempt_count': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingOutboxMessages(
    DatabaseExecutor db,
  ) async {
    return db.query(
      outboxTable,
      where: "status IN ('pending','failed') AND sent = 0",
      orderBy: 'created_at ASC',
      limit: 50,
    );
  }

  static Future<void> markOutboxMessageSent(
    DatabaseExecutor db,
    String messageId,
  ) async {
    await db.update(
      outboxTable,
      {
        'sent': 1,
        'status': 'sent',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
        'next_attempt_at': null,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  static Future<void> cleanupOldEvents(DatabaseExecutor db) async {
    final monthAgo = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    await db.delete(
      'domain_events',
      where: 'created_at < ? AND processed = ?',
      whereArgs: [monthAgo, 1],
    );

    await db.delete(
      outboxTable,
      where: "created_at < ? AND status = 'sent' AND sent = 1",
      whereArgs: [monthAgo],
    );
  }

  // 📊 إحصائيات النظام
  static Future<Map<String, dynamic>> getSystemStats(
    DatabaseExecutor db,
  ) async {
    final tables = [
      'users',
      'clients',
      'repairs',
      'invoices',
      'employees',
      'suppliers',
      'purchases',
      'cheques',
      'vouchers',
    ];

    final stats = <String, int>{};

    for (final table in tables) {
      try {
        final result = await db.rawQuery(
          'SELECT COUNT(*) as count FROM $table',
        );
        stats[table] = (result.first['count'] as num?)?.toInt() ?? 0;
      } catch (_) {
        stats[table] = 0;
      }
    }

    final pendingRepairs = await db.rawQuery(
      'SELECT COUNT(*) as count FROM repairs WHERE isArchived = 0',
    );
    stats['pending_repairs'] =
        (pendingRepairs.first['count'] as num?)?.toInt() ?? 0;

    final pendingCheques = await db.rawQuery(
      'SELECT COUNT(*) as count FROM cheques '
      'WHERE status IN ("pending", "deposited")',
    );
    stats['pending_cheques'] =
        (pendingCheques.first['count'] as num?)?.toInt() ?? 0;

    final unprocessedEvents = await db.rawQuery(
      'SELECT COUNT(*) as count FROM domain_events WHERE processed = 0',
    );
    stats['unprocessed_events'] =
        (unprocessedEvents.first['count'] as num?)?.toInt() ?? 0;

    final pendingOutbox = await db.rawQuery(
      "SELECT COUNT(*) as count FROM $outboxTable "
      "WHERE status IN ('pending','failed') AND sent = 0",
    );
    stats['pending_outbox'] =
        (pendingOutbox.first['count'] as num?)?.toInt() ?? 0;

    return stats;
  }
}
