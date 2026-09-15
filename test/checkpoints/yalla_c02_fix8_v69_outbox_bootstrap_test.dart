import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('C02 FIX8 upgrades a legacy v69 outbox in place', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE outbox_messages(
        id TEXT PRIMARY KEY,
        channel TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sent INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.insert('outbox_messages', {
      'id': 'legacy-pending',
      'channel': 'sync',
      'payload_json': '{"legacy":true}',
      'created_at': '2026-08-01T10:00:00.000Z',
      'sent': 0,
    });
    await db.insert('outbox_messages', {
      'id': 'legacy-sent',
      'channel': 'sync',
      'payload_json': '{"legacy":true}',
      'created_at': '2026-08-01T11:00:00.000Z',
      'sent': 1,
    });

    await DatabaseMigration.ensureP04OutboxCompatibilityBeforeValidation(db);

    final info = await db.rawQuery('PRAGMA table_info(outbox_messages)');
    final columns = info.map((row) => row['name']?.toString()).toSet();

    expect(
        columns,
        containsAll(<String>[
          'operation',
          'entity_type',
          'entity_id',
          'idempotency_key',
          'updated_at',
          'status',
          'attempt_count',
          'next_attempt_at',
          'last_error',
        ]));

    final rows = await db.query(
      'outbox_messages',
      orderBy: 'created_at ASC',
    );
    expect(rows, hasLength(2));
    expect(rows.first['id'], 'legacy-pending');
    expect(rows.first['status'], 'pending');
    expect(rows.first['sent'], 0);
    expect(rows.last['id'], 'legacy-sent');
    expect(rows.last['status'], 'sent');
    expect(rows.last['sent'], 1);

    final stats = await OfflineOutboxService.queueStats(db);
    expect(stats.pending, 1);
    expect(stats.failed, 0);
    expect(stats.sending, 0);
  });

  test('C02 FIX8 creates the technical outbox if it is absent', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await DatabaseMigration.ensureP04OutboxCompatibilityBeforeValidation(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='outbox_messages'",
    );
    expect(tables, hasLength(1));

    final stats = await OfflineOutboxService.queueStats(db);
    expect(stats.pending, 0);
    expect(stats.failed, 0);
    expect(stats.sending, 0);
  });

  test('C02 FIX8 executes Outbox compatibility before validation', () {
    final source = File(
      'lib/core/services/db/database_migration.dart',
    ).readAsStringSync();
    final constants = File(
      'lib/core/services/db/database_constants.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('await ensureP04OutboxCompatibilityBeforeValidation(db);'),
    );
    expect(source, contains('if (oldV < 70) await _upgradeV70(db);'));
    expect(source, contains('await _validateDatabase(db);'));
    expect(constants, contains('static const int dbVersion = 76;'));
  });
}
