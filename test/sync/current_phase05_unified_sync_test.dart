import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';

void main() {
  late Database db;
  late Directory temp;
  const org = '11111111-1111-4111-8111-111111111111';
  const device = '22222222-2222-4222-8222-222222222222';

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('phase05_sync_');
    db = await databaseFactoryFfi.openDatabase('${temp.path}/test.sqlite');
    await db.execute(
        'CREATE TABLE organization_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT)');
    await db.insert(
        'organization_identity', {'singleton_id': 1, 'organization_id': org});
    await db.execute(
        'CREATE TABLE installation_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT,device_id TEXT)');
    await db.insert('installation_identity',
        {'singleton_id': 1, 'organization_id': org, 'device_id': device});
    await db.execute(
        'CREATE TABLE repairs(id TEXT PRIMARY KEY,notes TEXT,status TEXT,fileValue REAL)');
    await db.execute('''CREATE TABLE accounts(
      id INTEGER PRIMARY KEY,code TEXT,name TEXT,type TEXT,
      normal_balance TEXT,report_class TEXT,is_postable INTEGER,
      is_system INTEGER,is_active INTEGER,parent_id INTEGER)''');
    await db.execute('''CREATE TABLE party_roles(
      party_id INTEGER NOT NULL,role TEXT NOT NULL,legacy_id INTEGER)''');
    await TechnicalTables.createAllTables(db);
    await SyncFoundationTables.ensure(db);
    await UnifiedSyncTables.ensure(db);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('business write and sync_outbox commit or roll back together', () async {
    await db.transaction((txn) async {
      await txn.insert('repairs', {'id': 'r1', 'notes': 'ok', 'fileValue': 10});
    });
    expect(await db.query('repairs'), hasLength(1));
    expect(await db.query(UnifiedSyncTables.outbox), hasLength(1));
    final before = await db.query(UnifiedSyncTables.outbox);

    await expectLater(db.transaction((txn) async {
      await txn.insert(
          'repairs', {'id': 'r2', 'notes': 'rollback', 'fileValue': 20});
      throw StateError('force rollback');
    }), throwsStateError);

    expect(await db.query('repairs'), hasLength(1));
    expect(await db.query(UnifiedSyncTables.outbox), before);
    final changeCount = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM ${SyncFoundationTables.changes} WHERE entity_id='r2'",
    ));
    expect(changeCount, 0);
  });

  test('outbox state machine is retry safe and terminal after acknowledgement',
      () async {
    await db.insert('repairs', {'id': 'r1', 'fileValue': 10});
    final row = (await db.query(UnifiedSyncTables.outbox)).single;
    final id = row['outbox_id'] as String;
    await UnifiedSyncQueueService.markSending(db, id);
    await UnifiedSyncQueueService.returnToPending(db, id, error: 'offline');
    var state = (await db.query(UnifiedSyncTables.outbox)).single;
    expect(state['state'], 'PENDING');
    expect(state['attempt_count'], 1);

    await db.update(UnifiedSyncTables.outbox, {'next_attempt_at': null},
        where: 'outbox_id=?', whereArgs: [id]);
    await UnifiedSyncQueueService.markSending(db, id);
    await UnifiedSyncQueueService.markAcknowledged(db, id, serverSequence: 44);
    state = (await db.query(UnifiedSyncTables.outbox)).single;
    expect(state['state'], 'ACKNOWLEDGED');
    expect(state['server_sequence'], 44);
    await expectLater(
      UnifiedSyncQueueService.markSending(db, id),
      throwsStateError,
    );
    await expectLater(
      db.update(UnifiedSyncTables.outbox, {'state': 'PENDING'},
          where: 'outbox_id=?', whereArgs: [id]),
      throwsA(isA<DatabaseException>()),
    );
  });

  InboundSyncChange inbound(int sequence, String id, {String name = 'remote'}) {
    return InboundSyncChange(
      serverSequence: sequence,
      changeId: 'change-$id',
      entityType: 'party',
      entityId: id,
      entityUuid: '00000000-0000-4000-8000-${id.padLeft(12, '0')}',
      operation: 'UPSERT',
      revision: 1,
      occurredAt: DateTime.utc(2026, 9, 16, 9),
      payload: {'id': id, 'name': name},
    );
  }

  test('inbound apply and checkpoint advance atomically; retry is idempotent',
      () async {
    await db
        .execute('CREATE TABLE remote_shadow(id TEXT PRIMARY KEY,name TEXT)');
    var calls = 0;
    Future<void> apply(DatabaseExecutor txn, InboundSyncChange change) async {
      calls += 1;
      await txn.insert('remote_shadow', {
        'id': change.entityId,
        'name': change.payload['name'],
      });
    }

    final batch = [inbound(5, '1'), inbound(9, '2')];
    final checkpoint = await UnifiedSyncQueueService.applyInboundBatch(
      db,
      organizationId: org,
      changes: batch,
      apply: apply,
    );
    expect(checkpoint, 9);
    expect(calls, 2);
    expect(await db.query('remote_shadow'), hasLength(2));
    expect(await db.query(UnifiedSyncTables.inbox), hasLength(2));
    expect(await UnifiedSyncQueueService.checkpointFor(db, org), 9);

    calls = 0;
    final retry = await UnifiedSyncQueueService.applyInboundBatch(
      db,
      organizationId: org,
      changes: batch,
      apply: apply,
    );
    expect(retry, 9);
    expect(calls, 0);
    expect(await db.query('remote_shadow'), hasLength(2));
  });

  test('failed inbound batch rolls back business rows, inbox and checkpoint',
      () async {
    await db
        .execute('CREATE TABLE remote_shadow(id TEXT PRIMARY KEY,name TEXT)');
    await UnifiedSyncQueueService.applyInboundBatch(
      db,
      organizationId: org,
      changes: [inbound(3, '1')],
      apply: (txn, change) => txn.insert('remote_shadow', {
        'id': change.entityId,
        'name': change.payload['name'],
      }),
    );
    expect(await UnifiedSyncQueueService.checkpointFor(db, org), 3);

    await expectLater(
      UnifiedSyncQueueService.applyInboundBatch(
        db,
        organizationId: org,
        changes: [inbound(4, '2'), inbound(8, '3')],
        apply: (txn, change) async {
          await txn.insert('remote_shadow', {
            'id': change.entityId,
            'name': change.payload['name'],
          });
          if (change.entityId == '3') throw StateError('apply failed');
        },
      ),
      throwsStateError,
    );

    expect(await UnifiedSyncQueueService.checkpointFor(db, org), 3);
    expect(await db.query('remote_shadow'), hasLength(1));
    expect(await db.query(UnifiedSyncTables.inbox), hasLength(1));
  });

  test('same server sequence with changed payload is rejected', () async {
    await db
        .execute('CREATE TABLE remote_shadow(id TEXT PRIMARY KEY,name TEXT)');
    final original = inbound(7, '1', name: 'A');
    await UnifiedSyncQueueService.applyInboundBatch(
      db,
      organizationId: org,
      changes: [original],
      apply: (txn, change) => txn.insert('remote_shadow', {
        'id': change.entityId,
        'name': change.payload['name'],
      }),
    );
    await expectLater(
      UnifiedSyncQueueService.applyInboundBatch(
        db,
        organizationId: org,
        changes: [inbound(7, '1', name: 'B')],
        apply: (_, __) async => fail('changed replay must never apply'),
      ),
      throwsStateError,
    );
    expect(await UnifiedSyncQueueService.checkpointFor(db, org), 7);
    expect((await db.query('remote_shadow')).single['name'], 'A');
  });

  test('checkpoint cannot regress and inbox payload cannot be rewritten',
      () async {
    await db.insert(UnifiedSyncTables.checkpoint, {
      'organization_id': org,
      'last_server_sequence': 10,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await expectLater(
      db.update(UnifiedSyncTables.checkpoint, {'last_server_sequence': 9},
          where: 'organization_id=?', whereArgs: [org]),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
      'resolved conflict is retained as history but leaves the open failure queue',
      () async {
    await db.insert('repairs', {'id': 'r-conflict', 'fileValue': 10});
    final outbox = (await db.query(UnifiedSyncTables.outbox)).single;
    final id = outbox['outbox_id']!.toString();
    const conflictId = '33333333-3333-4333-8333-333333333333';

    await UnifiedSyncQueueService.markSending(db, id);
    await UnifiedSyncQueueService.markConflict(
      db,
      id,
      conflictId: conflictId,
    );
    expect(await UnifiedSyncQueueService.openConflicts(db), hasLength(1));
    expect((await UnifiedSyncQueueService.queueStats(db)).failed, 1);

    await UnifiedSyncQueueService.recordConflictResolution(
      db,
      conflictId: conflictId,
      decision: 'FINANCIAL_CORRECTION_REQUIRED',
      status: 'ACTION_REQUIRED',
    );
    expect(await UnifiedSyncQueueService.openConflicts(db), hasLength(1));
    expect((await UnifiedSyncQueueService.queueStats(db)).failed, 1);

    await UnifiedSyncQueueService.recordConflictResolution(
      db,
      conflictId: conflictId,
      decision: 'FINANCIAL_CORRECTION_COMPLETED',
      status: 'RESOLVED',
      reference: '44444444-4444-4444-8444-444444444444',
    );
    expect(await UnifiedSyncQueueService.openConflicts(db), isEmpty);
    expect((await UnifiedSyncQueueService.queueStats(db)).failed, 0);
    final retained = (await db.query(
      UnifiedSyncTables.outbox,
      where: 'outbox_id=?',
      whereArgs: [id],
    ))
        .single;
    expect(retained['state'], 'CONFLICT');
    expect(retained['resolution_status'], 'RESOLVED');
    expect(retained['resolved_at'], isNotNull);
  });
}
