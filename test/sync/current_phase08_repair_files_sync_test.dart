import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/repair_tables.dart';
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
      final existing = sequences[changeId];
      final serverSequence = existing ?? ++sequence;
      if (existing == null) {
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
    name TEXT NOT NULL,pid TEXT,phone TEXT,address TEXT,account_id INTEGER
  )''');
  await RepairTables.createAllTables(db);
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
  await RepairTables.ensureRepairsSchema(db);
  return db;
}

Future<int> _pendingCount(Database db) async {
  final rows = await db.rawQuery(
    "SELECT COUNT(*) AS c FROM sync_outbox WHERE state='PENDING'",
  );
  return (rows.single['c'] as num).toInt();
}

Future<Map<String, Object?>> _registry(
  Database db,
  String entityType,
  String localId,
) async {
  return Map<String, Object?>.from((await db.query(
    SyncFoundationTables.registry,
    where: 'entity_type=? AND local_id=?',
    whereArgs: [entityType, localId],
  ))
      .single);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Phase 08 Repair file, lines and workflow replicate by stable UUIDs',
      () async {
    final root = await Directory.systemTemp.createTemp('phase08_repair_sync_');
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
        name: 'Repair Owner',
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
        whereArgs: ['Repair Owner'],
      ))
          .single;
      final roleA = (await dbA.query(
        'party_roles',
        where: 'party_id=? AND role=?',
        whereArgs: [partyA['id'], 'CUSTOMER'],
      ))
          .single;
      final clientA = int.parse(roleA['legacy_id']!.toString());
      final partyIdentityA =
          await _registry(dbA, 'party', partyA['id']!.toString());
      final partyUuid = partyIdentityA['entity_uuid']!.toString();

      final roleB = (await dbB.query(
        'party_roles',
        where:
            'role=? AND party_id=(SELECT local_id FROM sync_entity_registry WHERE entity_type=? AND entity_uuid=?)',
        whereArgs: ['CUSTOMER', 'party', partyUuid],
      ))
          .single;
      final clientB = int.parse(roleB['legacy_id']!.toString());
      expect(clientB, isNot(clientA));
      final vehicleA = await VehicleService.upsertFromRepairOn(
        dbA,
        number: '22-333-44',
        type: 'Test Car',
        model: '2026',
        clientId: clientA,
      );
      expect((await coordinatorA.cycle(database: dbA)).acknowledged, 1);
      expect((await coordinatorB.cycle(database: dbB)).pulled, 1);
      final vehicleIdentityA =
          await _registry(dbA, 'vehicle', vehicleA.toString());
      final vehicleUuid = vehicleIdentityA['entity_uuid']!.toString();
      final vehicleIdentityB = (await dbB.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND entity_uuid=?',
        whereArgs: ['vehicle', vehicleUuid],
      ))
          .single;
      final vehicleB = int.parse(vehicleIdentityB['local_id']!.toString());
      expect(vehicleB, isNot(vehicleA));

      const repairIdA = 'repair-local-a';
      final now = DateTime.utc(2026, 9, 16, 18).toIso8601String();
      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.insert('repairs', {
          'id': repairIdA,
          'vehicleModel': '2026',
          'vehicleType': 'Test Car',
          'vehicleNumber': '22-333-44',
          'beneficiaryType': 'أفراد',
          'beneficiaryName': 'Repair Owner',
          'client_id': clientA,
          'customer_party_uuid': partyUuid,
          'vehicle_entity_uuid': vehicleUuid,
          'is_active': 1,
          'status': 'QUOTE',
          'notes': 'Initial repair note',
          'fileValue': 1500.0,
          'paidAmount': 250.0,
          'imagePaths': '["a-local.jpg"]',
          'invoice_id': 'local-only-invoice',
          'created_at': now,
          'updated_at': now,
        });
      });
      final repairIdentityA = await _registry(dbA, 'repair', repairIdA);
      final repairUuid = repairIdentityA['entity_uuid']!.toString();
      final repairPush = await coordinatorA.cycle(database: dbA);
      expect(repairPush.acknowledged, greaterThanOrEqualTo(1));
      final repairPull = await coordinatorB.cycle(database: dbB);
      expect(repairPull.pulled, greaterThanOrEqualTo(1));

      final repairIdentityB = (await dbB.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND entity_uuid=?',
        whereArgs: ['repair', repairUuid],
      ))
          .single;
      final repairIdB = repairIdentityB['local_id']!.toString();
      expect(repairIdB, isNot(repairIdA));
      final repairB = (await dbB.query(
        'repairs',
        where: 'id=?',
        whereArgs: [repairIdB],
      ))
          .single;
      expect(repairB['client_id'], clientB);
      expect(repairB['customer_party_uuid'], partyUuid);
      expect(repairB['vehicle_entity_uuid'], vehicleUuid);
      expect(repairB['vehicleNumber'], '22-333-44');
      expect(repairB['notes'], 'Initial repair note');
      expect(repairB['fileValue'], isNull);
      expect(repairB['paidAmount'], isNull);
      expect(repairB['imagePaths'], isNull);
      expect(repairB['invoice_id'], isNull);
      expect(await _pendingCount(dbB), 0);

      const lineIdA = 'line-local-a';
      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.insert('repair_lines', {
          'id': lineIdA,
          'repair_id': repairIdA,
          'line_type': 'part',
          'name': 'Front lamp',
          'qty': 2.0,
          'price': 100.0,
          'total': 200.0,
          'notes': 'OEM',
          'created_at': DateTime.utc(2026, 9, 16, 18, 5).toIso8601String(),
        });
      });
      final linePush = await coordinatorA.cycle(database: dbA);
      expect(linePush.acknowledged, greaterThanOrEqualTo(1));
      final linePull = await coordinatorB.cycle(database: dbB);
      expect(linePull.pulled, greaterThanOrEqualTo(1));
      final lineIdentityA = await _registry(dbA, 'repair_line', lineIdA);
      final lineUuid = lineIdentityA['entity_uuid']!.toString();
      final lineIdentityB = (await dbB.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND entity_uuid=?',
        whereArgs: ['repair_line', lineUuid],
      ))
          .single;
      final lineIdB = lineIdentityB['local_id']!.toString();
      expect(lineIdB, isNot(lineIdA));
      final lineB = (await dbB.query(
        'repair_lines',
        where: 'id=?',
        whereArgs: [lineIdB],
      ))
          .single;
      expect(lineB['repair_id'], repairIdB);
      expect(lineB['name'], 'Front lamp');
      expect(lineB['total'], 200.0);
      expect(await _pendingCount(dbB), 0);

      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.insert('repair_workflow', {
          'repair_id': repairIdA,
          'stage': 'ESTIMATE',
          'damage_assessment': 'Front impact',
          'quote_number': 'Q-08',
          'responsible_employee_id': 'local-employee-a',
          'created_at': DateTime.utc(2026, 9, 16, 18, 6).toIso8601String(),
          'updated_at': DateTime.utc(2026, 9, 16, 18, 6).toIso8601String(),
        });
      });
      final workflowPush = await coordinatorA.cycle(database: dbA);
      expect(workflowPush.acknowledged, greaterThanOrEqualTo(1));
      final workflowPull = await coordinatorB.cycle(database: dbB);
      expect(workflowPull.pulled, greaterThanOrEqualTo(1));
      final workflowB = (await dbB.query(
        'repair_workflow',
        where: 'repair_id=?',
        whereArgs: [repairIdB],
      ))
          .single;
      expect(workflowB['stage'], 'ESTIMATE');
      expect(workflowB['damage_assessment'], 'Front impact');
      expect(workflowB['responsible_employee_id'], isNull);
      expect(await _pendingCount(dbB), 0);
      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
          'repairs',
          {
            'notes': 'Updated across devices',
            'fileValue': 9999.0,
            'updated_at': DateTime.utc(2026, 9, 16, 18, 10).toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [repairIdA],
        );
      });
      expect((await coordinatorA.cycle(database: dbA)).acknowledged,
          greaterThanOrEqualTo(1));
      expect((await coordinatorB.cycle(database: dbB)).pulled,
          greaterThanOrEqualTo(1));
      var updatedB = (await dbB.query(
        'repairs',
        where: 'id=?',
        whereArgs: [repairIdB],
      ))
          .single;
      expect(updatedB['notes'], 'Updated across devices');
      expect(updatedB['fileValue'], isNull);

      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
          'repairs',
          {
            'is_active': 0,
            'isArchived': 1,
            'updated_at': DateTime.utc(2026, 9, 16, 18, 15).toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [repairIdA],
        );
      });
      expect((await coordinatorA.cycle(database: dbA)).acknowledged,
          greaterThanOrEqualTo(1));
      expect((await coordinatorB.cycle(database: dbB)).pulled,
          greaterThanOrEqualTo(1));
      updatedB = (await dbB.query(
        'repairs',
        where: 'id=?',
        whereArgs: [repairIdB],
      ))
          .single;
      expect(updatedB['is_active'], 0);
      expect(updatedB['isArchived'], 1);

      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
          'repairs',
          {
            'is_active': 1,
            'isArchived': 0,
            'notes': 'Restored repair',
            'updated_at': DateTime.utc(2026, 9, 16, 18, 20).toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [repairIdA],
        );
      });
      expect((await coordinatorA.cycle(database: dbA)).acknowledged,
          greaterThanOrEqualTo(1));
      expect((await coordinatorB.cycle(database: dbB)).pulled,
          greaterThanOrEqualTo(1));
      updatedB = (await dbB.query(
        'repairs',
        where: 'id=?',
        whereArgs: [repairIdB],
      ))
          .single;
      expect(updatedB['is_active'], 1);
      expect(updatedB['isArchived'], 0);
      expect(updatedB['notes'], 'Restored repair');
      final checkpointBefore = (await dbB.query(
        UnifiedSyncTables.checkpoint,
      ))
          .single['last_server_sequence'];
      final retry = await coordinatorB.cycle(database: dbB);
      expect(retry.pulled, 0);
      expect(
        (await dbB.query(UnifiedSyncTables.checkpoint))
            .single['last_server_sequence'],
        checkpointBefore,
      );
      expect(await _pendingCount(dbB), 0);
      expect(await dbB.query('repairs'), hasLength(1));
      expect(await dbB.query('repair_lines'), hasLength(1));
      expect(await dbB.query('repair_workflow'), hasLength(1));
    } finally {
      await dbA.close();
      await dbB.close();
      await root.delete(recursive: true);
    }
  });
}
