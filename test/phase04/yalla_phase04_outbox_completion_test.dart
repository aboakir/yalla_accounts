import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('P04.2C upgrades a legacy outbox without losing its row', () async {
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
      'id': 'legacy-1',
      'channel': 'sync',
      'payload_json': jsonEncode({'legacy': true}),
      'created_at': '2026-09-02T12:00:00.000Z',
      'sent': 0,
    });

    await TechnicalTables.ensureP04OutboxSchema(db);

    final rows = await db.query('outbox_messages');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'legacy-1');
    expect(rows.single['status'], 'pending');
    expect(rows.single['attempt_count'], 0);
    expect(rows.single['updated_at'], '2026-09-02T12:00:00.000Z');

    final info = await db.rawQuery('PRAGMA table_info(outbox_messages)');
    final names = info.map((row) => row['name']).toSet();
    expect(
        names,
        containsAll(<String>{
          'operation',
          'entity_type',
          'entity_id',
          'idempotency_key',
          'updated_at',
          'status',
          'attempt_count',
          'next_attempt_at',
          'last_error',
        }));
  });

  test('P04.2C enqueue is JSON + idempotent and restart recovers sending',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await TechnicalTables.createAllTables(db);

    const key = 'repair:r-1:create';

    expect(
      await OfflineOutboxService.enqueue(
        db,
        channel: OfflineOutboxService.channelSync,
        operation: 'UPSERT',
        entityType: 'repair',
        entityId: 'r-1',
        idempotencyKey: key,
        payload: const {'schema': 1, 'entity_id': 'r-1'},
      ),
      isTrue,
    );

    expect(
      await OfflineOutboxService.enqueue(
        db,
        channel: OfflineOutboxService.channelSync,
        operation: 'UPSERT',
        entityType: 'repair',
        entityId: 'r-1',
        idempotencyKey: key,
        payload: const {'schema': 1, 'entity_id': 'r-1'},
      ),
      isFalse,
    );

    final row = (await OfflineOutboxService.ready(db: db)).single;
    expect(jsonDecode(row['payload_json'] as String)['entity_id'], 'r-1');

    final id = row['id'] as String;
    await OfflineOutboxService.markSending(db, id);
    await OfflineOutboxService.resetInterruptedSending(db);

    final recovered = (await db.query(
      TechnicalTables.outboxTable,
      where: 'id = ?',
      whereArgs: [id],
    ))
        .single;

    expect(recovered['status'], 'failed');
    expect(recovered['sent'], 0);
  });

  test('P04.2C current-v69 ensure lives in post-init, not oldV<68 only', () {
    final migration = File(
      'lib/core/services/db/database_migration.dart',
    ).readAsStringSync();

    final postInitStart =
        migration.indexOf('static Future<void> _postInit(Database db) async');
    final postInitEnd = migration.indexOf(
      'static Future<void> _ensureVoucherExtraColumns',
      postInitStart,
    );

    expect(postInitStart, greaterThanOrEqualTo(0));
    expect(postInitEnd, greaterThan(postInitStart));

    final postInit = migration.substring(postInitStart, postInitEnd);
    expect(
      postInit,
      contains('await TechnicalTables.ensureP04OutboxSchema(db);'),
    );
    expect(
      postInit,
      contains('await OfflineOutboxService.resetInterruptedSending(db);'),
    );

    final old68 = migration.indexOf('if (oldV < 68)');
    final old69 = migration.indexOf('if (oldV < 69)', old68);
    expect(old68, greaterThanOrEqualTo(0));
    expect(old69, greaterThan(old68));

    final historical = migration.substring(old68, old69);
    expect(
      historical,
      isNot(contains('TechnicalTables.ensureP04OutboxSchema')),
    );
  });

  test('P04.2C repair creation remains local-first transactional', () {
    final source = File(
      'lib/features/repairs/services/repair_save_service.dart',
    ).readAsStringSync();

    final tx = source.indexOf('await DBService.inTx((txn) async {');
    final outbox = source.indexOf('await OfflineOutboxService.enqueue(', tx);
    final end = source.indexOf("debugPrint('--- TX END OK ---');", tx);

    expect(tx, greaterThanOrEqualTo(0));
    expect(outbox, greaterThan(tx));
    expect(end, greaterThan(outbox));

    final body = source.substring(tx, end);
    expect(body, contains("idempotencyKey: 'repair:\$repairId:create'"));
    expect(body, isNot(contains('Connectivity')));
    expect(body, isNot(contains('http.')));
    expect(body, isNot(contains('Dio(')));
  });
}
