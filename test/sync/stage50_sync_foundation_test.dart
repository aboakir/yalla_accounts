import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_integrity_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';

void main() {
  late Database db;
  late Directory temp;
  const org = '11111111-1111-4111-8111-111111111111';
  const device = '22222222-2222-4222-8222-222222222222';

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('stage50_sync_');
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
    await db.execute(
        'CREATE TABLE invoices(id TEXT PRIMARY KEY,total REAL,status TEXT,date TEXT,post_to_gl INTEGER DEFAULT 0)');
    await TechnicalTables.createAllTables(db);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<Map<String, Object?>> identity(String id,
          {String type = 'repair'}) async =>
      (await SyncFoundationService.identityFor(db,
          entityType: type, localId: id))!;
  Future<List<Map<String, Object?>>> events(String id) =>
      db.query(SyncFoundationTables.changes,
          where: 'entity_id=?', whereArgs: [id], orderBy: 'sequence');

  test('additive upgrade retains all values and UUID across ensure and reopen',
      () async {
    await db.insert(
        'repairs', {'id': 'legacy-42', 'notes': 'old', 'fileValue': 123.45});
    final before = await db.query('repairs');
    final schema = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='repairs'");
    await db.transaction((txn) => SyncFoundationTables.ensure(txn));
    final first = await identity('legacy-42');
    expect(
        first['entity_uuid'],
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect((await events('legacy-42')).single['origin'], 'baseline');
    expect(
        (await events('legacy-42')).single['attribution_state'], 'historical');
    await SyncFoundationTables.ensure(db);
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${temp.path}/test.sqlite');
    await SyncFoundationTables.ensure(db);
    await SyncFoundationTables.validate(db);
    expect(await identity('legacy-42'), first);
    expect(await db.query('repairs'), before);
    expect(
        await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='repairs'"),
        schema);
    expect(await events('legacy-42'), hasLength(1));
    final savedEvent = (await events('legacy-42')).single;
    await expectLater(
        db.insert(SyncFoundationTables.changes,
            {...savedEvent, 'user_id': 'replacement'},
            conflictAlgorithm: ConflictAlgorithm.replace),
        throwsA(isA<DatabaseException>()));
    await expectLater(
        db.insert(SyncFoundationTables.registry,
            {...first, 'entity_uuid': 'ffffffff-ffff-4fff-8fff-ffffffffffff'},
            conflictAlgorithm: ConflictAlgorithm.replace),
        throwsA(isA<DatabaseException>()));
    await expectLater(
        db.update(SyncFoundationTables.changes, {'user_id': 'fake'}),
        throwsA(isA<DatabaseException>()));
    await expectLater(db.delete(SyncFoundationTables.changes),
        throwsA(isA<DatabaseException>()));
    await expectLater(db.delete(SyncFoundationTables.registry),
        throwsA(isA<DatabaseException>()));
  });

  test('document and attributed changes commit or roll back together',
      () async {
    await SyncFoundationTables.ensure(db);
    await db.transaction((txn) async {
      await txn.insert(SyncFoundationTables.context,
          {'singleton_id': 1, 'user_id': 'verified-user'});
      await txn.insert('repairs',
          {'id': 'r1', 'notes': 'start', 'status': 'active', 'fileValue': 10});
      await txn.update('repairs', {'notes': 'edited'},
          where: 'id=?', whereArgs: ['r1']);
      await txn.update('repairs', {'status': 'cancelled'},
          where: 'id=?', whereArgs: ['r1']);
      await txn.update('repairs', {'status': 'active'},
          where: 'id=?', whereArgs: ['r1']);
      await txn.delete(SyncFoundationTables.context);
    });
    final log = await events('r1');
    expect(log.map((r) => r['operation']),
        ['created', 'updated', 'voided', 'restored']);
    expect(log.map((r) => r['revision']), [1, 2, 3, 4]);
    for (final row in log) {
      expect(row['organization_id'], org);
      expect(row['device_id'], device);
      expect(row['user_id'], 'verified-user');
      expect(row['attribution_state'], 'attributed');
      expect(DateTime.tryParse(row['occurred_at'] as String), isNotNull);
    }
    await db.update('repairs', {'notes': 'edited'},
        where: 'id=?', whereArgs: ['r1']);
    expect(await events('r1'), hasLength(4));
    await expectLater(db.transaction((txn) async {
      await txn.update('repairs', {'fileValue': 999},
          where: 'id=?', whereArgs: ['r1']);
      await txn.insert('repairs', {'id': 'rolled-back', 'fileValue': 1});
      throw StateError('force rollback');
    }), throwsStateError);
    expect((await db.query('repairs')).single['fileValue'], 10);
    expect(await events('r1'), log);
    expect(
        await SyncFoundationService.identityFor(db,
            entityType: 'repair', localId: 'rolled-back'),
        isNull);
  });

  test(
      'missing preactivation identity does not block local saves or invent an actor',
      () async {
    await db.delete('installation_identity');
    await SyncFoundationTables.ensure(db);
    await SyncFoundationService.transaction(
        db, (txn) => txn.insert('repairs', {'id': 'offline', 'fileValue': 12}));
    final row = (await events('offline')).single;
    expect(row['attribution_state'], 'unavailable');
    expect(row['user_id'], isNull);
    expect(row['device_id'], isNull);
    expect(await db.query(SyncFoundationTables.context), isEmpty);
    expect(SyncFoundationService.remoteFinancialSyncEnabled, isFalse);
  });

  test('delete tombstone and restoration retain UUID; primary key cannot move',
      () async {
    await SyncFoundationTables.ensure(db);
    await db.insert('repairs', {'id': 'r1', 'fileValue': 10});
    final uuid = (await identity('r1'))['entity_uuid'];
    await db.delete('repairs', where: 'id=?', whereArgs: ['r1']);
    expect((await identity('r1'))['is_voided'], 1);
    await db.insert('repairs', {'id': 'r1', 'fileValue': 10});
    expect((await identity('r1'))['entity_uuid'], uuid);
    expect((await identity('r1'))['is_voided'], 0);
    expect((await events('r1')).map((r) => r['operation']),
        ['created', 'voided', 'restored']);
    await expectLater(
        db.update('repairs', {'id': 'other'}, where: 'id=?', whereArgs: ['r1']),
        throwsA(isA<DatabaseException>()));
  });

  test(
      'outbox acknowledgement records the exact queued revision once atomically',
      () async {
    await SyncFoundationTables.ensure(db);
    await db.transaction((txn) async {
      await txn.insert('repairs', {'id': 'r1', 'fileValue': 10});
      await OfflineOutboxService.enqueue(txn,
          channel: 'sync',
          operation: 'UPSERT',
          entityType: 'repair',
          entityId: 'r1',
          idempotencyKey: 'repair:r1:create',
          payload: {'entity_id': 'r1'});
    });
    final outbox = (await OfflineOutboxService.ready(db: db)).single;
    await db.update('repairs', {'notes': 'later'},
        where: 'id=?', whereArgs: ['r1']);
    await expectLater(db.transaction((txn) async {
      await OfflineOutboxService.markSent(txn, outbox['id'] as String);
      throw StateError('no commit');
    }), throwsStateError);
    expect(
        (await events('r1')).where((r) => r['operation'] == 'synced'), isEmpty);
    await OfflineOutboxService.markSent(db, outbox['id'] as String);
    await OfflineOutboxService.markSent(db, outbox['id'] as String);
    final ack =
        (await events('r1')).where((r) => r['operation'] == 'synced').single;
    expect(ack['revision'], 1);
    expect((await identity('r1'))['revision'], 2);
  });

  test(
      'concurrent, financial and delete/update candidates are quarantined idempotently',
      () async {
    await SyncFoundationTables.ensure(db);
    await db.insert('repairs',
        {'id': 'r1', 'notes': 'local', 'status': 'active', 'fileValue': 100});
    final uuid = (await identity('r1'))['entity_uuid'] as String;
    RemoteSyncCandidate candidate(String id,
            {int base = 0,
            double amount = 120,
            SyncChangeOperation op = SyncChangeOperation.updated}) =>
        RemoteSyncCandidate(
            changeId: id,
            organizationId: org,
            deviceId: device,
            userId: 'remote-user',
            entityUuid: uuid,
            entityType: 'repair',
            baseRevision: base,
            operation: op,
            occurredAt: DateTime.utc(2026, 9, 9),
            snapshot: {
              'id': 'r1',
              'notes': 'remote',
              'status': 'active',
              'fileValue': amount
            });
    final original = await db.query('repairs');
    final first = await SyncFoundationService.quarantineCandidate(
        db, candidate('remote-1'));
    expect(first.reasons,
        containsAll(['concurrent_update', 'financial_value_difference']));
    expect(first.applied, isFalse);
    expect(first.requiresReview, isTrue);
    final retry = await SyncFoundationService.quarantineCandidate(
        db, candidate('remote-1'));
    expect(retry.duplicate, isTrue);
    expect(retry.candidateId, first.candidateId);
    await expectLater(
        SyncFoundationService.quarantineCandidate(
            db, candidate('remote-1', amount: 130)),
        throwsStateError);
    expect(await db.query(SyncFoundationTables.candidates), hasLength(1));
    expect(await db.query(SyncFoundationTables.conflicts), hasLength(1));
    expect(await db.query('repairs'), original);
    await db.delete('repairs', where: 'id=?', whereArgs: ['r1']);
    final deleted = await SyncFoundationService.quarantineCandidate(
        db, candidate('remote-2', base: 1, amount: 100));
    expect(deleted.reasons, contains('delete_vs_update'));
    expect(await db.query('repairs'), isEmpty);
    await expectLater(db.delete(SyncFoundationTables.conflicts),
        throwsA(isA<DatabaseException>()));
  });

  test('no-conflict proposal still requires review and never silently merges',
      () async {
    await SyncFoundationTables.ensure(db);
    await db
        .insert('repairs', {'id': 'r1', 'notes': 'local', 'fileValue': 100});
    final row = await identity('r1');
    final result = await SyncFoundationService.quarantineCandidate(
        db,
        RemoteSyncCandidate(
            changeId: 'remote-safe',
            organizationId: org,
            deviceId: device,
            userId: 'remote-user',
            entityUuid: row['entity_uuid'] as String,
            entityType: 'repair',
            baseRevision: 1,
            operation: SyncChangeOperation.updated,
            occurredAt: DateTime.utc(2026, 9, 9),
            snapshot: {
              ...Map<String, Object?>.from(
                  jsonDecode(row['snapshot_json'] as String) as Map),
              'notes': 'proposed'
            }));
    expect(result.hasConflict, isFalse);
    expect(result.requiresReview, isTrue);
    expect(result.applied, isFalse);
    expect((await db.query('repairs')).single['notes'], 'local');
  });

  test(
      'sync foundation cannot bypass posted document or duplicate GL source guards',
      () async {
    await db.execute(
        'CREATE TABLE gl_entries(id INTEGER PRIMARY KEY,date TEXT,source TEXT,source_id TEXT,created_by TEXT)');
    await db.execute(
        'CREATE TABLE gl_lines(id INTEGER PRIMARY KEY,entry_id INTEGER,debit REAL,credit REAL)');
    await AccountingIntegrityTables.ensure(db);
    await SyncFoundationTables.ensure(db);
    await db.insert('invoices',
        {'id': 'inv', 'total': 100, 'date': '2026-09-09', 'post_to_gl': 1});
    await db.insert('gl_entries', {
      'id': 1,
      'source': 'INVOICE',
      'source_id': 'inv',
      'date': '2026-09-09',
      'created_by': 'recorded-creator'
    });
    final before = await db.query('invoices');
    final logs = await events('inv');
    await expectLater(
        db.update('invoices', {'total': 999},
            where: 'id=?', whereArgs: ['inv']),
        throwsA(isA<DatabaseException>()));
    await expectLater(db.delete('invoices', where: 'id=?', whereArgs: ['inv']),
        throwsA(isA<DatabaseException>()));
    await expectLater(
        db.insert('gl_entries', {
          'id': 2,
          'source': 'INVOICE',
          'source_id': 'inv',
          'date': '2026-09-09'
        }),
        throwsA(isA<DatabaseException>()));
    expect(await db.query('invoices'), before);
    expect(await events('inv'), logs);
    final glLog =
        (await events('1')).where((r) => r['entity_type'] == 'gl_entry').single;
    expect(glLog['user_id'], 'recorded-creator');
    final row = await identity('inv', type: 'invoice');
    final result = await SyncFoundationService.quarantineCandidate(
        db,
        RemoteSyncCandidate(
            changeId: 'remote-posted',
            organizationId: org,
            deviceId: device,
            userId: 'remote-user',
            entityUuid: row['entity_uuid'] as String,
            entityType: 'invoice',
            baseRevision: 1,
            operation: SyncChangeOperation.updated,
            occurredAt: DateTime.utc(2026, 9, 9),
            snapshot: {...before.single, 'total': 999}));
    expect(
        result.reasons,
        containsAll([
          'financial_value_difference',
          'posted_document_requires_existing_reversal_flow'
        ]));
    expect(await db.query('invoices'), before);
  });
  test(
      'line updates advance parent revision and replacement keeps before-state',
      () async {
    await db.execute(
        'CREATE TABLE repair_lines(id TEXT PRIMARY KEY,repair_id TEXT,total REAL)');
    await SyncFoundationTables.ensure(db);
    await db
        .insert('repairs', {'id': 'r1', 'notes': 'before', 'fileValue': 10});
    await db.insert(
        'repair_lines', {'id': 'line-1', 'repair_id': 'r1', 'total': 10});
    expect((await identity('r1'))['revision'], 2);
    await db.update('repair_lines', {'total': 20},
        where: 'id=?', whereArgs: ['line-1']);
    expect((await identity('r1'))['revision'], 3);
    expect((await db.query('repairs')).single['fileValue'], 10);
    final uuid = (await identity('r1'))['entity_uuid'];
    await db.insert(
        'repairs', {'id': 'r1', 'notes': 'replacement', 'fileValue': 10},
        conflictAlgorithm: ConflictAlgorithm.replace);
    expect((await identity('r1'))['entity_uuid'], uuid);
    final last = (await events('r1')).last;
    expect(last['operation'], 'updated');
    expect(
        (jsonDecode(last['before_json'] as String) as Map)['notes'], 'before');
    expect((jsonDecode(last['after_json'] as String) as Map)['notes'],
        'replacement');
  });
}
