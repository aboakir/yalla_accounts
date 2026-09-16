import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_inbound_router.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

const org = '11111111-1111-4111-8111-111111111111';

class MemorySyncServer implements SyncV3Transport {
  final List<SyncV3PullChange> _changes = [];
  final Map<String, int> _sequences = {};
  int _sequence = 0;

  @override
  bool get isConfigured => true;

  int get acceptedChanges => _changes.length;

  @override
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows) async {
    final results = <SyncV3PushResult>[];
    for (final row in rows) {
      final changeId = row['change_id']!.toString();
      final existing = _sequences[changeId];
      final sequence = existing ?? ++_sequence;
      if (existing == null) {
        _sequences[changeId] = sequence;
        _changes.add(SyncV3PullChange(
          serverSequence: sequence,
          changeId: changeId,
          organizationId: row['organization_id']!.toString(),
          entityType: row['entity_type']!.toString(),
          entityId: row['entity_id']!.toString(),
          entityUuid: row['entity_uuid']!.toString(),
          operation: row['operation']!.toString(),
          revision: (row['revision'] as num).toInt(),
          occurredAt: DateTime.parse(row['occurred_at']!.toString()),
          payload: Map<String, Object?>.from(
            jsonDecode(row['payload_json']!.toString()) as Map,
          ),
        ));
      }
      results.add(SyncV3PushResult(
        changeId: changeId,
        idempotencyKey: row['idempotency_key']!.toString(),
        disposition: 'ACKNOWLEDGED',
        serverSequence: sequence,
      ));
    }
    return SyncV3PushResponse(results);
  }

  @override
  Future<SyncV3PullResponse> pull({
    required int afterServerSequence,
    int limit = 200,
  }) async {
    final available = _changes
        .where((change) => change.serverSequence > afterServerSequence)
        .take(limit)
        .toList(growable: false);
    final next =
        available.isEmpty ? afterServerSequence : available.last.serverSequence;
    return SyncV3PullResponse(
      fromSequence: afterServerSequence,
      nextSequence: next,
      hasMore: _changes.any((change) => change.serverSequence > next),
      changes: available,
    );
  }
}

Future<Database> openDeviceDb(String path, String deviceId) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('''CREATE TABLE organization_identity(
    singleton_id INTEGER PRIMARY KEY,
    organization_id TEXT NOT NULL
  )''');
  await db.insert('organization_identity', {
    'singleton_id': 1,
    'organization_id': org,
  });
  await db.execute('''CREATE TABLE installation_identity(
    singleton_id INTEGER PRIMARY KEY,
    organization_id TEXT NOT NULL,
    device_id TEXT NOT NULL
  )''');
  await db.insert('installation_identity', {
    'singleton_id': 1,
    'organization_id': org,
    'device_id': deviceId,
  });
  await db.execute('''CREATE TABLE clients(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL,
    phone TEXT,email TEXT,address TEXT,notes TEXT,account_id INTEGER
  )''');
  await db.execute('''CREATE TABLE suppliers(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    pid TEXT,
    phone TEXT,
    address TEXT,
    account_id INTEGER
  )''');
  await PartyTables.ensure(db);
  await SyncFoundationTables.ensure(db);
  await UnifiedSyncTables.ensure(db);
  return db;
}

Future<Map<String, Object?>> canonicalParty(Database db) async {
  final rows = await db.query(
    'parties',
    where: 'merged_into_id IS NULL',
    orderBy: 'created_at ASC',
  );
  expect(rows, hasLength(1));
  return Map<String, Object?>.from(rows.single);
}

Future<int> outboxCount(Database db) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_outbox');
  return (rows.single['c'] as num).toInt();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Phase 06 A to server to B preserves canonical Party identity',
      () async {
    final root = await Directory.systemTemp.createTemp('phase06_party_sync_');
    final dbA = await openDeviceDb(
      '${root.path}/a.sqlite',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final dbB = await openDeviceDb(
      '${root.path}/b.sqlite',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    final server = MemorySyncServer();
    final coordinatorA = UnifiedSyncCoordinatorV3(status: SyncStateService());
    final coordinatorB = UnifiedSyncCoordinatorV3(status: SyncStateService());
    coordinatorA.configureTransport(server);
    coordinatorB.configureTransport(server);
    coordinatorB.configureInboundApplier(UnifiedSyncInboundRouter.apply);

    try {
      await PartyFinancialService.createParty(
        name: 'Master Party One',
        phone: '0599000000',
        address: 'Bethlehem',
        customer: true,
        supplier: true,
        database: dbA,
      );
      expect(await outboxCount(dbA), 1);
      expect(await outboxCount(dbB), 0);

      var pushed = await coordinatorA.cycle(database: dbA);
      expect(pushed.acknowledged, 1);
      expect(server.acceptedChanges, 1);

      var pulled = await coordinatorB.cycle(database: dbB);
      expect(pulled.pulled, 1);
      expect(await outboxCount(dbB), 0);

      final partyA = await canonicalParty(dbA);
      final partyB = await canonicalParty(dbB);
      expect(partyB['display_name'], partyA['display_name']);
      expect(partyB['phone'], partyA['phone']);
      expect(jsonDecode(partyB['role_codes']!.toString()),
          ['CUSTOMER', 'SUPPLIER']);
      expect(await dbB.query('clients'), hasLength(1));
      expect(await dbB.query('suppliers'), hasLength(1));
      expect(await dbB.query('party_roles'), hasLength(2));

      final regA = (await dbA.query(SyncFoundationTables.registry,
              where: "entity_type='party'"))
          .single;
      final regB = (await dbB.query(SyncFoundationTables.registry,
              where: "entity_type='party'"))
          .single;
      expect(regB['entity_uuid'], regA['entity_uuid']);
      expect(regB['revision'], regA['revision']);

      await dbA.update(
        'parties',
        {
          'display_name': 'Master Party Updated',
          'phone': '0599111111',
          'updated_at': DateTime.utc(2026, 9, 16, 12).toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [partyA['id']],
      );
      expect(await outboxCount(dbA), 2);
      pushed = await coordinatorA.cycle(database: dbA);
      expect(pushed.acknowledged, 1);
      pulled = await coordinatorB.cycle(database: dbB);
      expect(pulled.pulled, 1);

      final updatedB = await canonicalParty(dbB);
      expect(updatedB['display_name'], 'Master Party Updated');
      expect(updatedB['phone'], '0599111111');
      expect(
          (await dbB.query('clients')).single['name'], 'Master Party Updated');
      expect((await dbB.query('suppliers')).single['name'],
          'Master Party Updated');
      expect(await outboxCount(dbB), 0);

      await dbA.update(
        'parties',
        {
          'is_active': 0,
          'updated_at': DateTime.utc(2026, 9, 16, 13).toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [partyA['id']],
      );
      expect(await outboxCount(dbA), 3);
      pushed = await coordinatorA.cycle(database: dbA);
      expect(pushed.acknowledged, 1);
      pulled = await coordinatorB.cycle(database: dbB);
      expect(pulled.pulled, 1);

      final tombstonedB = await canonicalParty(dbB);
      expect(tombstonedB['is_active'], 0);
      final tombstoneRegistry = (await dbB.query(
        SyncFoundationTables.registry,
        where: "entity_type='party'",
      ))
          .single;
      expect(tombstoneRegistry['is_voided'], 1);
      expect(tombstoneRegistry['revision'], 3);
      expect(await outboxCount(dbB), 0);

      final checkpointBeforeRetry = (await dbB.query(
        UnifiedSyncTables.checkpoint,
      ))
          .single['last_server_sequence'];
      pulled = await coordinatorB.cycle(database: dbB);
      expect(pulled.pulled, 0);
      expect(server.acceptedChanges, 3);
      expect((await dbB.query('parties')), hasLength(1));
      expect((await dbB.query('clients')), hasLength(1));
      expect((await dbB.query('suppliers')), hasLength(1));
      expect(
          (await dbB.query(UnifiedSyncTables.checkpoint))
              .single['last_server_sequence'],
          checkpointBeforeRetry);
    } finally {
      await dbA.close();
      await dbB.close();
      await root.delete(recursive: true);
    }
  });

  test('Phase 06 legacy client/supplier wire records do not block checkpoint',
      () async {
    final root = await Directory.systemTemp.createTemp('phase06_legacy_wire_');
    final db = await openDeviceDb(
      '${root.path}/b.sqlite',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    );
    try {
      final coordinator = UnifiedSyncCoordinatorV3(status: SyncStateService());
      final server = MemorySyncServer();
      coordinator.configureTransport(server);
      coordinator.configureInboundApplier(UnifiedSyncInboundRouter.apply);

      server._sequence = 2;
      server._changes.addAll([
        SyncV3PullChange(
          serverSequence: 1,
          changeId: '10000000-0000-4000-8000-000000000001',
          organizationId: org,
          entityType: 'client',
          entityId: '77',
          entityUuid: '10000000-0000-4000-8000-000000000002',
          operation: 'UPSERT',
          revision: 1,
          occurredAt: DateTime.utc(2026, 9, 16),
          payload: const {'name': 'Legacy Client'},
        ),
        SyncV3PullChange(
          serverSequence: 2,
          changeId: '20000000-0000-4000-8000-000000000001',
          organizationId: org,
          entityType: 'supplier',
          entityId: '88',
          entityUuid: '20000000-0000-4000-8000-000000000002',
          operation: 'UPSERT',
          revision: 1,
          occurredAt: DateTime.utc(2026, 9, 16),
          payload: const {'name': 'Legacy Supplier'},
        ),
      ]);

      final result = await coordinator.cycle(database: db);
      expect(result.pulled, 2);
      expect(await db.query('clients'), isEmpty);
      expect(await db.query('suppliers'), isEmpty);
      final checkpoint = (await db.query(UnifiedSyncTables.checkpoint)).single;
      expect(checkpoint['last_server_sequence'], 2);
      expect(await outboxCount(db), 0);
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
