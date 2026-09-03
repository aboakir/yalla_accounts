// 📁 lib/core/services/db/tables/technical_tables.dart
import 'package:sqflite/sqflite.dart';

class TechnicalTables {
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

  static Future<void> _ensureDomainEventsIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_domain_events_type ON domain_events(type);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_domain_events_created ON domain_events(created_at);');
  }

  // 📤 جدول الرسائل الصادرة
  static Future<void> _createOutboxTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox_messages(
        id TEXT PRIMARY KEY,
        channel TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sent INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_outbox_channel ON outbox_messages(channel);');
  }

  // 🔄 ترقية الجداول
  static Future<void> onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 22) {
      await _createDomainEventsTable(db);
      await _createOutboxTable(db);
    }
  }

  // 🎯 واجهات الاستخدام
  static Future<void> logDomainEvent(
      DatabaseExecutor db, String type, Map<String, dynamic> payload) async {
    await db.insert('domain_events', {
      'id': '${DateTime.now().millisecondsSinceEpoch}_$type',
      'type': type,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'processed': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingDomainEvents(
      DatabaseExecutor db) async {
    return await db.query(
      'domain_events',
      where: 'processed = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
      limit: 100,
    );
  }

  static Future<void> markDomainEventProcessed(
      DatabaseExecutor db, String eventId) async {
    await db.update(
      'domain_events',
      {'processed': 1},
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  static Future<void> addOutboxMessage(
      DatabaseExecutor db, String channel, Map<String, dynamic> payload) async {
    await db.insert('outbox_messages', {
      'id': '${DateTime.now().millisecondsSinceEpoch}_$channel',
      'channel': channel,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'sent': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingOutboxMessages(
      DatabaseExecutor db) async {
    return await db.query(
      'outbox_messages',
      where: 'sent = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
      limit: 50,
    );
  }

  static Future<void> markOutboxMessageSent(
      DatabaseExecutor db, String messageId) async {
    await db.update(
      'outbox_messages',
      {'sent': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  static Future<void> cleanupOldEvents(DatabaseExecutor db) async {
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    await db.delete(
      'domain_events',
      where: 'created_at < ? AND processed = ?',
      whereArgs: [monthAgo.toIso8601String(), 1],
    );

    await db.delete(
      'outbox_messages',
      where: 'created_at < ? AND sent = ?',
      whereArgs: [monthAgo.toIso8601String(), 1],
    );
  }

  // 📊 إحصائيات النظام
  static Future<Map<String, dynamic>> getSystemStats(
      DatabaseExecutor db) async {
    final tables = [
      'users',
      'clients',
      'repairs',
      'invoices',
      'employees',
      'suppliers',
      'purchases',
      'cheques',
      'vouchers'
    ];

    final stats = <String, int>{};

    for (final table in tables) {
      try {
        final result =
            await db.rawQuery('SELECT COUNT(*) as count FROM $table');
        stats[table] = (result.first['count'] as num?)?.toInt() ?? 0;
      } catch (e) {
        stats[table] = 0;
      }
    }

    // إحصائيات إضافية
    final pendingRepairs = await db
        .rawQuery('SELECT COUNT(*) as count FROM repairs WHERE isArchived = 0');
    stats['pending_repairs'] =
        (pendingRepairs.first['count'] as num?)?.toInt() ?? 0;

    final pendingCheques = await db.rawQuery(
        'SELECT COUNT(*) as count FROM cheques WHERE status IN ("pending", "deposited")');
    stats['pending_cheques'] =
        (pendingCheques.first['count'] as num?)?.toInt() ?? 0;

    final unprocessedEvents = await db.rawQuery(
        'SELECT COUNT(*) as count FROM domain_events WHERE processed = 0');
    stats['unprocessed_events'] =
        (unprocessedEvents.first['count'] as num?)?.toInt() ?? 0;

    return stats;
  }
}

// دالة مساعدة للـ JSON
String jsonEncode(Map<String, dynamic> data) {
  return data.toString(); // يمكن استبدالها بمكتبة JSON حقيقية
}
