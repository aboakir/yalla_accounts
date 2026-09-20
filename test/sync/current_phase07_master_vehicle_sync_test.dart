import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_inbound_router.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

const org = '11111111-1111-4111-8111-111111111111';

class _MemorySyncServer implements SyncV3Transport {
  final List<SyncV3PullChange> changes = [];
  final Map<String, int> sequences = {};
  int sequence = 0;

  @override
  bool get isConfigured => true;
  @override
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows) async {
    final results = <SyncV3PushResult>[];
    for (final row in rows) {
      final changeId = row['change_id']!.toString();
      final current = sequences[changeId];
      final serverSequence = current ?? ++sequence;
      if (current == null) {
        sequences[changeId] = serverSequence;
        changes.add(SyncV3PullChange(
          serverSequence: serverSequence,
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
        serverSequence: serverSequence,
      ));
    }
    return SyncV3PushResponse(results);
  }

  @override
  Future<SyncV3PullResponse> pull({
    required int afterServerSequence,
    int limit = 200,
  }) async {
    final available = changes
        .where((change) => change.serverSequence > afterServerSequence)
        .take(limit)
        .toList(growable: false);
    final next =
        available.isEmpty ? afterServerSequence : available.last.serverSequence;
    return SyncV3PullResponse(
      fromSequence: afterServerSequence,
      nextSequence: next,
      hasMore: changes.any((change) => change.serverSequence > next),
      changes: available,
    );
  }
}

Future<Database> _openDeviceDb(
  String path,
  String deviceId, {
  bool preseed = false,
}) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
      'CREATE TABLE organization_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT NOT NULL)');
  await db.insert(
      'organization_identity', {'singleton_id': 1, 'organization_id': org});
  await db.execute(
      'CREATE TABLE installation_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT NOT NULL,device_id TEXT NOT NULL)');
  await db.insert('installation_identity',
      {'singleton_id': 1, 'organization_id': org, 'device_id': deviceId});
  await db.execute('''CREATE TABLE clients(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL,
    phone TEXT,email TEXT,address TEXT,notes TEXT,account_id INTEGER
  )''');
  await db.execute('''CREATE TABLE suppliers(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,pid TEXT,phone TEXT,address TEXT,account_id INTEGER
  )''');
  await db.execute('''CREATE TABLE repairs(
    id TEXT PRIMARY KEY,
    vehicleNumber TEXT,
    vehicleType TEXT,
    vehicleModel TEXT,
    client_id INTEGER,
    receivedDate TEXT,
    created_at TEXT
  )''');
  if (preseed) {
    await db.insert('clients', {
      'name': 'Local Dummy',
      'type': 'أفراد',
      'phone': '',
      'email': '',
      'address': '',
      'notes': '',
    });
  }
  await db.execute('''CREATE TABLE accounts(
    id INTEGER PRIMARY KEY,code TEXT,name TEXT,type TEXT,
    normal_balance TEXT,report_class TEXT,is_postable INTEGER,
    is_system INTEGER,is_active INTEGER,parent_id INTEGER)''');
  await PartyTables.ensure(db);
  await VehicleTables.ensure(db);
  if (preseed) {
    final now = DateTime.utc(2026, 9, 16).toIso8601String();
    await db.insert('vehicles', {
      'normalized_number': 'DUMMY1',
      'number': 'DUMMY-1',
      'type': 'dummy',
      'model': '2020',
      'client_id': 1,
      'notes': '',
      'created_at': now,
      'updated_at': now,
    });
  }
  await SyncFoundationTables.ensure(db);
  await UnifiedSyncTables.ensure(db);
  await VehicleTables.ensure(db);
  return db;
}

Future<int> _pendingCount(Database db) async {
  final rows = await db.rawQuery(
    "SELECT COUNT(*) AS c FROM sync_outbox WHERE state='PENDING'",
  );
  return (rows.single['c'] as num).toInt();
}

Future<Map<String, Object?>> _vehicleByNumber(
  Database db,
  String number,
) async {
  final normalized = VehicleTables.normalizeNumber(number);
  return Map<String, Object?>.from((await db.query(
    'vehicles',
    where: 'normalized_number=?',
    whereArgs: [normalized],
  ))
      .single);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Phase 07 A to server to B preserves Vehicle and owner Party UUIDs',
      () async {
    final root = await Directory.systemTemp.createTemp('phase07_vehicle_sync_');
    final dbA = await _openDeviceDb(
      '${root.path}/a.sqlite',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final dbB = await _openDeviceDb(
      '${root.path}/b.sqlite',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      preseed: true,
    );
    final server = _MemorySyncServer();
    final coordinatorA = UnifiedSyncCoordinatorV3(status: SyncStateService());
    final coordinatorB = UnifiedSyncCoordinatorV3(status: SyncStateService());
    coordinatorA.configureTransport(server);
    coordinatorB.configureTransport(server);
    coordinatorB.configureInboundApplier(UnifiedSyncInboundRouter.apply);

    try {
      await PartyFinancialService.createParty(
        name: 'Vehicle Owner',
        phone: '0599000000',
        address: 'Bethlehem',
        customer: true,
        supplier: false,
        database: dbA,
      );
      expect(await _pendingCount(dbA), 1);
      expect((await coordinatorA.cycle(database: dbA)).acknowledged, 1);
      expect((await coordinatorB.cycle(database: dbB)).pulled, 1);

      final partyA = (await dbA.query(
        'parties',
        where: 'display_name=?',
        whereArgs: ['Vehicle Owner'],
      ))
          .single;
      final partyB = (await dbB.query(
        'parties',
        where: 'display_name=?',
        whereArgs: ['Vehicle Owner'],
      ))
          .single;
      final customerA = int.parse((await dbA.query(
        'party_roles',
        columns: const ['legacy_id'],
        where: 'party_id=? AND role=?',
        whereArgs: [partyA['id'], 'CUSTOMER'],
      ))
          .single['legacy_id']!
          .toString());
      final customerB = int.parse((await dbB.query(
        'party_roles',
        columns: const ['legacy_id'],
        where: 'party_id=? AND role=?',
        whereArgs: [partyB['id'], 'CUSTOMER'],
      ))
          .single['legacy_id']!
          .toString());
      expect(customerB, isNot(customerA));
      await VehicleService.upsertFromRepairOn(
        dbA,
        number: '12-345-67',
        type: 'Toyota',
        model: '2025',
        clientId: customerA,
      );
      expect(await _pendingCount(dbA), 1);
      expect((await coordinatorA.cycle(database: dbA)).acknowledged, 1);

      final vehicleWire = server.changes.last;
      expect(vehicleWire.entityType, 'vehicle');
      expect(vehicleWire.payload.containsKey('id'), isFalse);
      expect(vehicleWire.payload.containsKey('client_id'), isFalse);
      expect(vehicleWire.payload['owner_party_uuid'], isNotNull);

      expect((await coordinatorB.cycle(database: dbB)).pulled, 1);
      final vehicleA = await _vehicleByNumber(dbA, '12-345-67');
      final vehicleB = await _vehicleByNumber(dbB, '12-345-67');
      expect(vehicleA['id'], isNot(vehicleB['id']));
      expect(vehicleB['client_id'], customerB);
      expect(vehicleB['owner_party_uuid'], vehicleA['owner_party_uuid']);
      expect(vehicleB['is_active'], 1);

      final regA = (await dbA.query(
        SyncFoundationTables.registry,
        where: "entity_type='vehicle' AND local_id=?",
        whereArgs: [vehicleA['id'].toString()],
      ))
          .single;
      final regB = (await dbB.query(
        SyncFoundationTables.registry,
        where: "entity_type='vehicle' AND local_id=?",
        whereArgs: [vehicleB['id'].toString()],
      ))
          .single;
      expect(regB['entity_uuid'], regA['entity_uuid']);
      expect(regB['revision'], regA['revision']);
      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
            'vehicles',
            {
              'model': '2026',
              'notes': 'updated on A',
              'updated_at': DateTime.utc(2026, 9, 16, 12).toIso8601String(),
            },
            where: 'id=?',
            whereArgs: [vehicleA['id']]);
      });
      expect((await coordinatorA.cycle(database: dbA)).acknowledged, 1);
      expect((await coordinatorB.cycle(database: dbB)).pulled, 1);
      var currentB = await _vehicleByNumber(dbB, '12-345-67');
      expect(currentB['model'], '2026');
      expect(currentB['notes'], 'updated on A');

      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
            'vehicles',
            {
              'is_active': 0,
              'updated_at': DateTime.utc(2026, 9, 16, 13).toIso8601String(),
            },
            where: 'id=?',
            whereArgs: [vehicleA['id']]);
      });
      expect((await coordinatorA.cycle(database: dbA)).acknowledged, 1);
      expect(server.changes.last.operation, 'DELETE');
      expect((await coordinatorB.cycle(database: dbB)).pulled, 1);
      currentB = await _vehicleByNumber(dbB, '12-345-67');
      expect(currentB['is_active'], 0);

      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
            'vehicles',
            {
              'is_active': 1,
              'updated_at': DateTime.utc(2026, 9, 16, 14).toIso8601String(),
            },
            where: 'id=?',
            whereArgs: [vehicleA['id']]);
      });
      expect((await coordinatorA.cycle(database: dbA)).acknowledged, 1);
      final restoreWire = server.changes.last;
      expect(restoreWire.operation, 'UPSERT');
      expect(restoreWire.payload['_sync_restore'], true);
      expect((await coordinatorB.cycle(database: dbB)).pulled, 1);
      currentB = await _vehicleByNumber(dbB, '12-345-67');
      expect(currentB['is_active'], 1);
      final restoredRegB = (await dbB.query(
        SyncFoundationTables.registry,
        where: "entity_type='vehicle' AND local_id=?",
        whereArgs: [currentB['id'].toString()],
      ))
          .single;
      expect(restoredRegB['entity_uuid'], regA['entity_uuid']);
      expect(restoredRegB['revision'], 4);

      final checkpointBeforeRetry = (await dbB.query(
        UnifiedSyncTables.checkpoint,
      ))
          .single['last_server_sequence'];
      expect((await coordinatorB.cycle(database: dbB)).pulled, 0);
      expect(
        (await dbB.query(UnifiedSyncTables.checkpoint))
            .single['last_server_sequence'],
        checkpointBeforeRetry,
      );
      expect(
          (await dbB.rawQuery(
            "SELECT COUNT(*) AS c FROM sync_outbox WHERE state='PENDING'",
          ))
              .single['c'],
          0);
    } finally {
      await dbA.close();
      await dbB.close();
      await root.delete(recursive: true);
    }
  });
}
