import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await TechnicalTables.createAllTables(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('P04.2 Outbox is durable JSON and idempotent', () async {
    const key = 'repair:r-1:create';

    final first = await OfflineOutboxService.enqueue(
      db,
      channel: OfflineOutboxService.channelSync,
      operation: 'UPSERT',
      entityType: 'repair',
      entityId: 'r-1',
      idempotencyKey: key,
      payload: const {
        'schema': 1,
        'entity_id': 'r-1',
      },
    );

    final duplicate = await OfflineOutboxService.enqueue(
      db,
      channel: OfflineOutboxService.channelSync,
      operation: 'UPSERT',
      entityType: 'repair',
      entityId: 'r-1',
      idempotencyKey: key,
      payload: const {
        'schema': 1,
        'entity_id': 'r-1',
      },
    );

    expect(first, isTrue);
    expect(duplicate, isFalse);
    expect(await OfflineOutboxService.pendingCount(db), 1);

    final rows = await OfflineOutboxService.ready(db: db);
    expect(rows, hasLength(1));
    expect(rows.single['status'], 'pending');
    expect(rows.single['idempotency_key'], key);

    final decoded = jsonDecode(rows.single['payload_json'] as String);
    expect(decoded['entity_id'], 'r-1');
  });

  test('P04.2 failed delivery is retryable and later markSent is final',
      () async {
    await OfflineOutboxService.enqueue(
      db,
      channel: OfflineOutboxService.channelSync,
      operation: 'UPSERT',
      entityType: 'repair',
      entityId: 'r-2',
      idempotencyKey: 'repair:r-2:create',
      payload: const {'entity_id': 'r-2'},
    );

    final row = (await OfflineOutboxService.ready(db: db)).single;
    final id = row['id'] as String;
    final now = DateTime.utc(2026, 9, 2, 12);

    await OfflineOutboxService.markFailed(
      db,
      id,
      error: 'offline',
      now: now,
    );

    final failed = (await db.query(
      TechnicalTables.outboxTable,
      where: 'id = ?',
      whereArgs: [id],
    ))
        .single;

    expect(failed['status'], 'failed');
    expect(failed['attempt_count'], 1);
    expect(failed['last_error'], 'offline');
    expect(failed['next_attempt_at'], isNotNull);

    expect(
      await OfflineOutboxService.ready(db: db, now: now),
      isEmpty,
    );

    await OfflineOutboxService.markSent(db, id);
    expect(await OfflineOutboxService.pendingCount(db), 0);

    final sent = (await db.query(
      TechnicalTables.outboxTable,
      where: 'id = ?',
      whereArgs: [id],
    ))
        .single;
    expect(sent['status'], 'sent');
    expect(sent['sent'], 1);
  });

  test('P04.2 source contract keeps repair save local-first', () {
    final source = File(
      'lib/features/repairs/services/repair_save_service.dart',
    ).readAsStringSync();

    final txStart = source.indexOf('await DBService.inTx((txn) async {');
    final enqueue =
        source.indexOf('await OfflineOutboxService.enqueue(', txStart);
    final txEnd = source.indexOf("debugPrint('--- TX END OK ---');", txStart);

    expect(txStart, greaterThanOrEqualTo(0));
    expect(enqueue, greaterThan(txStart));
    expect(txEnd, greaterThan(enqueue));

    final transactionBody = source.substring(txStart, txEnd);
    expect(transactionBody, contains("entityType: 'repair'"));
    expect(transactionBody,
        contains("idempotencyKey: 'repair:\$repairId:create'"));
    expect(transactionBody, isNot(contains('Connectivity')));
    expect(transactionBody, isNot(contains('http.')));
    expect(transactionBody, isNot(contains('Dio(')));
  });
}
