import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/inventory_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_inbound_router.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';
import 'package:yalla_accounts/features/inventory/services/canonical_inventory_service.dart';

const _org = '11111111-1111-4111-8111-111111111111';

Future<Database> _openDb(String path, String device,
    {bool preseed = false}) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
      'CREATE TABLE organization_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT NOT NULL)');
  await db.insert(
      'organization_identity', {'singleton_id': 1, 'organization_id': _org});
  await db.execute(
      'CREATE TABLE installation_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT NOT NULL,device_id TEXT NOT NULL)');
  await db.insert('installation_identity',
      {'singleton_id': 1, 'organization_id': _org, 'device_id': device});
  await InventoryTables.ensure(db);
  await SyncFoundationTables.ensure(db);
  if (preseed) {
    final now = DateTime.utc(2026, 9, 17).toIso8601String();
    await db.insert(InventoryTables.items, {
      'name': 'Local Dummy Item',
      'item_kind': 'PART',
      'unit': 'pcs',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert(InventoryTables.warehouses, {
      'code': 'LOCAL-DUMMY',
      'name': 'Local Dummy Warehouse',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }
  await SyncFoundationTables.ensure(db);
  await UnifiedSyncTables.ensure(db);
  return db;
}

Future<String> _uuid(Database db, String type, Object localId) async {
  final row = (await db.query(SyncFoundationTables.registry,
          columns: const ['entity_uuid'],
          where: 'entity_type=? AND local_id=?',
          whereArgs: [type, localId.toString()]))
      .single;
  return row['entity_uuid']!.toString();
}

Future<Map<String, Object?>> _outbox(Database db, String uuid) async =>
    Map<String, Object?>.from((await db.query(UnifiedSyncTables.outbox,
            where: 'entity_uuid=?',
            whereArgs: [uuid],
            orderBy: 'created_at DESC',
            limit: 1))
        .single);

InboundSyncChange _inbound(Map<String, Object?> row, int sequence) =>
    InboundSyncChange(
      serverSequence: sequence,
      changeId: row['change_id']!.toString(),
      entityType: row['entity_type']!.toString(),
      entityId: row['entity_id']!.toString(),
      entityUuid: row['entity_uuid']!.toString(),
      operation: row['operation']!.toString(),
      revision: (row['revision'] as num).toInt(),
      occurredAt: DateTime.parse(row['occurred_at']!.toString()),
      payload: Map<String, Object?>.from(
        jsonDecode(row['payload_json']!.toString()) as Map,
      ),
    );

Future<void> _apply(Database db, Map<String, Object?> row, int sequence) =>
    SyncFoundationService.transaction(
      db,
      (txn) => UnifiedSyncInboundRouter.apply(txn, _inbound(row, sequence)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Phase 10 movement ledger derives stock and is append-only', () async {
    final root = await Directory.systemTemp.createTemp('phase10_inventory_');
    final db = await _openDb(
        '${root.path}/ledger.sqlite', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    DatabaseMigration.useDatabaseForTesting(db);
    try {
      final item = await CanonicalInventoryService.createItem(
          name: 'Front Lamp', sku: 'LAMP-001', oemNumber: '92101-TEST');
      final mainWh = await CanonicalInventoryService.createWarehouse(
          code: 'MAIN', name: 'Main Warehouse');
      final secondWh = await CanonicalInventoryService.createWarehouse(
          code: 'SECOND', name: 'Second Warehouse');
      await CanonicalInventoryService.recordMovement(
          itemId: item,
          warehouseId: mainWh,
          movementType: 'PURCHASE_RECEIPT',
          onHandDelta: 10,
          unitCost: 50);
      await CanonicalInventoryService.recordMovement(
          itemId: item,
          warehouseId: mainWh,
          movementType: 'RESERVATION',
          onHandDelta: 0,
          reservedDelta: 3);
      await CanonicalInventoryService.recordMovement(
          itemId: item,
          warehouseId: mainWh,
          movementType: 'RELEASE',
          onHandDelta: 0,
          reservedDelta: -1);
      final sale = await CanonicalInventoryService.recordMovement(
          itemId: item,
          warehouseId: mainWh,
          movementType: 'SALE',
          onHandDelta: -2);
      var balance = await CanonicalInventoryService.stockBalance(
          itemId: item, warehouseId: mainWh);
      expect(balance.onHand, 8);
      expect(balance.reserved, 2);
      expect(balance.available, 6);

      expect(
          await CanonicalInventoryService.transfer(
              itemId: item,
              fromWarehouseId: mainWh,
              toWarehouseId: secondWh,
              quantity: 3),
          hasLength(2));
      balance = await CanonicalInventoryService.stockBalance(
          itemId: item, warehouseId: mainWh);
      final second = await CanonicalInventoryService.stockBalance(
          itemId: item, warehouseId: secondWh);
      expect([balance.onHand, balance.reserved, balance.available], [5, 2, 3]);
      expect([second.onHand, second.reserved, second.available], [3, 0, 3]);

      await CanonicalInventoryService.reverseMovement(sale);
      balance = await CanonicalInventoryService.stockBalance(
          itemId: item, warehouseId: mainWh);
      expect([balance.onHand, balance.reserved, balance.available], [7, 2, 5]);
      expect(
          await db.query(InventoryTables.movements,
              where: 'id=?', whereArgs: [sale]),
          hasLength(1));

      await expectLater(
          CanonicalInventoryService.reverseMovement(sale),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              'INVENTORY_MOVEMENT_ALREADY_REVERSED')));
      await expectLater(
          CanonicalInventoryService.recordMovement(
              itemId: item,
              warehouseId: mainWh,
              movementType: 'SALE',
              onHandDelta: -99),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              'INVENTORY_INSUFFICIENT_AVAILABLE_STOCK')));
      await expectLater(
          db.update(InventoryTables.movements, {'note': 'illegal'},
              where: 'id=?', whereArgs: [sale]),
          throwsA(predicate(
              (e) => e.toString().contains('INVENTORY_MOVEMENT_APPEND_ONLY'))));
      await expectLater(
          db.delete(InventoryTables.movements,
              where: 'id=?', whereArgs: [sale]),
          throwsA(predicate(
              (e) => e.toString().contains('INVENTORY_MOVEMENT_APPEND_ONLY'))));

      final columns =
          (await db.rawQuery('PRAGMA table_info(${InventoryTables.items})'))
              .map((row) => row['name']?.toString())
              .toSet();
      expect(columns.contains('quantity'), isFalse);
      expect(columns.contains('quantityInStock'), isFalse);
      expect(columns.contains('stock_quantity'), isFalse);
      expect(await db.query(InventoryTables.stockByWarehouseView), isNotEmpty);
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      await root.delete(recursive: true);
    }
  });

  test('Phase 10 stable UUID wire maps different local ids and converges',
      () async {
    final root = await Directory.systemTemp.createTemp('phase10_sync_');
    final dbA = await _openDb(
        '${root.path}/a.sqlite', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    final dbB = await _openDb(
        '${root.path}/b.sqlite', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        preseed: true);
    try {
      DatabaseMigration.useDatabaseForTesting(dbA);
      final itemA = await CanonicalInventoryService.createItem(
          name: 'Kia Front Lamp', sku: 'KIA-LAMP-01');
      final whA = await CanonicalInventoryService.createWarehouse(
          code: 'MAIN', name: 'Main Warehouse');
      final receiptA = await CanonicalInventoryService.recordMovement(
          itemId: itemA,
          warehouseId: whA,
          movementType: 'PURCHASE_RECEIPT',
          onHandDelta: 5,
          unitCost: 40);
      final itemUuid = await _uuid(dbA, 'inventory_item', itemA);
      final whUuid = await _uuid(dbA, 'inventory_warehouse', whA);
      final receiptUuid = await _uuid(dbA, 'inventory_movement', receiptA);

      final pendingA = await UnifiedSyncQueueService.pendingOutbox(dbA);
      expect(pendingA.map((r) => r['entity_type']).take(3).toList(),
          ['inventory_item', 'inventory_warehouse', 'inventory_movement']);
      var sequence = 0;
      for (final row in pendingA) {
        await _apply(dbB, row, ++sequence);
      }
      final itemIdentityB = (await dbB.query(SyncFoundationTables.registry,
              where: 'entity_type=? AND entity_uuid=?',
              whereArgs: ['inventory_item', itemUuid]))
          .single;
      final whIdentityB = (await dbB.query(SyncFoundationTables.registry,
              where: 'entity_type=? AND entity_uuid=?',
              whereArgs: ['inventory_warehouse', whUuid]))
          .single;
      final itemB = int.parse(itemIdentityB['local_id']!.toString());
      final whB = int.parse(whIdentityB['local_id']!.toString());
      expect(itemB, isNot(itemA));
      expect(whB, isNot(whA));

      final movementB = (await dbB.query(InventoryTables.movements,
              where: 'item_entity_uuid=? AND warehouse_entity_uuid=?',
              whereArgs: [itemUuid, whUuid]))
          .single;
      expect(movementB['item_id'], itemB);
      expect(movementB['warehouse_id'], whB);
      final receiptWire = Map<String, Object?>.from(
          pendingA.singleWhere((r) => r['entity_uuid'] == receiptUuid));
      final payload = Map<String, Object?>.from(
          jsonDecode(receiptWire['payload_json']!.toString()) as Map);
      expect(payload['item_entity_uuid'], itemUuid);
      expect(payload['warehouse_entity_uuid'], whUuid);
      for (final key in const [
        'id',
        'item_id',
        'warehouse_id',
        'quantity',
        'quantityInStock',
        'stock_quantity',
        'on_hand',
        'reserved',
        'available'
      ]) {
        expect(payload.containsKey(key), isFalse);
      }
      final initialB = (await dbB.query(InventoryTables.stockByWarehouseView,
              where: 'item_id=? AND warehouse_id=?', whereArgs: [itemB, whB]))
          .single;
      expect(initialB['on_hand'], 5.0);

      DatabaseMigration.useDatabaseForTesting(dbA);
      final adjustA = await CanonicalInventoryService.recordMovement(
          itemId: itemA,
          warehouseId: whA,
          movementType: 'ADJUSTMENT',
          onHandDelta: 4);
      final adjustUuid = await _uuid(dbA, 'inventory_movement', adjustA);
      final adjustWire = await _outbox(dbA, adjustUuid);

      DatabaseMigration.useDatabaseForTesting(dbB);
      final saleB = await CanonicalInventoryService.recordMovement(
          itemId: itemB,
          warehouseId: whB,
          movementType: 'SALE',
          onHandDelta: -2);
      final saleUuid = await _uuid(dbB, 'inventory_movement', saleB);
      final saleWire = await _outbox(dbB, saleUuid);

      await _apply(dbB, adjustWire, ++sequence);
      await _apply(dbA, saleWire, ++sequence);
      final balanceA = (await dbA.query(InventoryTables.stockByWarehouseView,
              where: 'item_id=? AND warehouse_id=?', whereArgs: [itemA, whA]))
          .single;
      final balanceB = (await dbB.query(InventoryTables.stockByWarehouseView,
              where: 'item_id=? AND warehouse_id=?', whereArgs: [itemB, whB]))
          .single;
      expect(balanceA['on_hand'], 7.0);
      expect(balanceB['on_hand'], 7.0);
      expect(
          await dbA.query(InventoryTables.movements,
              where: 'item_entity_uuid=? AND warehouse_entity_uuid=?',
              whereArgs: [itemUuid, whUuid]),
          hasLength(3));
      expect(
          await dbB.query(InventoryTables.movements,
              where: 'item_entity_uuid=? AND warehouse_entity_uuid=?',
              whereArgs: [itemUuid, whUuid]),
          hasLength(3));

      final beforeRetry = await dbB.query(InventoryTables.movements,
          where: 'item_entity_uuid=? AND warehouse_entity_uuid=?',
          whereArgs: [itemUuid, whUuid]);
      await expectLater(
          _apply(dbB, adjustWire, ++sequence), throwsA(isA<StateError>()));
      final afterRetry = await dbB.query(InventoryTables.movements,
          where: 'item_entity_uuid=? AND warehouse_entity_uuid=?',
          whereArgs: [itemUuid, whUuid]);
      expect(afterRetry.length, beforeRetry.length);
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      await dbA.close();
      await dbB.close();
      await root.delete(recursive: true);
    }
  });
}
