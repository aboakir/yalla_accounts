import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/inventory/services/canonical_inventory_service.dart';
import 'package:yalla_accounts/features/inventory/services/inventory_operations_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late Database db;
  late int itemId;
  late int warehouseA;
  late int warehouseB;
  late int purchaseMovementId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('inventory_edge_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'edge.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);

    itemId = await CanonicalInventoryService.createItem(
      name: 'Transfer Primer',
      itemKind: 'RAW_MATERIAL',
      unit: 'liter',
      sku: 'TRANSFER-PRIMER',
      defaultPurchasePrice: 12.5,
    );
    warehouseA = await CanonicalInventoryService.createWarehouse(
      code: 'EDGE-A',
      name: 'Edge Warehouse A',
    );
    warehouseB = await CanonicalInventoryService.createWarehouse(
      code: 'EDGE-B',
      name: 'Edge Warehouse B',
    );
    purchaseMovementId = await CanonicalInventoryService.recordMovement(
      itemId: itemId,
      warehouseId: warehouseA,
      movementType: 'PURCHASE_RECEIPT',
      onHandDelta: 100,
      unitCost: 12.5,
      landedCost: 12.5,
      sourceEntityType: 'EDGE_PURCHASE',
      sourceReference: 'EDGE-P1',
    );
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('warehouse transfer preserves weighted inventory value', () async {
    await CanonicalInventoryService.recordMovement(
      itemId: itemId,
      warehouseId: warehouseB,
      movementType: 'PURCHASE_RECEIPT',
      onHandDelta: 10,
      unitCost: 20,
      landedCost: 20,
      sourceEntityType: 'EDGE_PURCHASE',
      sourceReference: 'EDGE-P2',
    );

    final ids = await CanonicalInventoryService.transfer(
      itemId: itemId,
      fromWarehouseId: warehouseA,
      toWarehouseId: warehouseB,
      quantity: 30,
      note: 'Value-preserving transfer',
    );
    expect(ids, hasLength(2));

    final a = await InventoryOperationsService.valuation(
      itemId: itemId,
      warehouseId: warehouseA,
      executor: db,
    );
    final b = await InventoryOperationsService.valuation(
      itemId: itemId,
      warehouseId: warehouseB,
      executor: db,
    );
    expect(a.onHand, closeTo(70, 0.001));
    expect(a.stockValue, closeTo(875, 0.01));
    expect(a.averageUnitCost, closeTo(12.5, 0.001));
    expect(b.onHand, closeTo(40, 0.001));
    expect(b.stockValue, closeTo(575, 0.01));
    expect(b.averageUnitCost, closeTo(14.375, 0.001));
    expect(a.stockValue + b.stockValue, closeTo(1450, 0.01));

    final transferRows = await db.query(
      'inventory_movements',
      where: "movement_type IN ('TRANSFER_OUT','TRANSFER_IN')",
      orderBy: 'id ASC',
    );
    expect(transferRows, hasLength(2));
    expect(
      (transferRows.first['unit_cost'] as num).toDouble(),
      closeTo(12.5, 0.001),
    );
    expect(
      (transferRows.last['unit_cost'] as num).toDouble(),
      closeTo(12.5, 0.001),
    );
    expect(transferRows.last['related_movement_uuid'], isNotNull);
  });

  test('reservation lifecycle changes available stock without changing on hand',
      () async {
    final reservationId = await CanonicalInventoryService.recordMovement(
      itemId: itemId,
      warehouseId: warehouseA,
      movementType: 'RESERVATION',
      onHandDelta: 0,
      reservedDelta: 20,
      sourceEntityType: 'EDGE_RESERVATION',
      sourceReference: 'RES-1',
    );
    var balance = await CanonicalInventoryService.stockBalance(
      itemId: itemId,
      warehouseId: warehouseA,
      executor: db,
    );
    expect(balance.onHand, 100);
    expect(balance.reserved, 20);
    expect(balance.available, 80);

    await expectLater(
      CanonicalInventoryService.recordMovement(
        itemId: itemId,
        warehouseId: warehouseA,
        movementType: 'RESERVATION',
        onHandDelta: 0,
        reservedDelta: 81,
        sourceEntityType: 'EDGE_RESERVATION',
        sourceReference: 'RES-OVER',
      ),
      throwsStateError,
    );

    final releaseId = await CanonicalInventoryService.recordMovement(
      itemId: itemId,
      warehouseId: warehouseA,
      movementType: 'RELEASE',
      onHandDelta: 0,
      reservedDelta: -5,
      sourceEntityType: 'EDGE_RELEASE',
      sourceReference: 'REL-1',
    );
    balance = await CanonicalInventoryService.stockBalance(
      itemId: itemId,
      warehouseId: warehouseA,
      executor: db,
    );
    expect(balance.reserved, 15);
    expect(balance.available, 85);

    await expectLater(
      CanonicalInventoryService.reverseMovement(reservationId),
      throwsStateError,
    );
    await CanonicalInventoryService.reverseMovement(releaseId);
    await CanonicalInventoryService.reverseMovement(reservationId);

    balance = await CanonicalInventoryService.stockBalance(
      itemId: itemId,
      warehouseId: warehouseA,
      executor: db,
    );
    expect(balance.onHand, 100);
    expect(balance.reserved, 0);
    expect(balance.available, 100);

    await expectLater(
      CanonicalInventoryService.reverseMovement(reservationId),
      throwsStateError,
    );
  });

  test('reversing an inbound movement cannot create negative stock', () async {
    await CanonicalInventoryService.recordMovement(
      itemId: itemId,
      warehouseId: warehouseA,
      movementType: 'SALE',
      onHandDelta: -10,
      unitCost: 12.5,
      landedCost: 12.5,
      sourceEntityType: 'EDGE_CONSUMPTION',
      sourceReference: 'USE-10',
    );

    await expectLater(
      CanonicalInventoryService.reverseMovement(purchaseMovementId),
      throwsStateError,
    );

    final balance = await CanonicalInventoryService.stockBalance(
      itemId: itemId,
      warehouseId: warehouseA,
      executor: db,
    );
    expect(balance.onHand, 90);
    expect(balance.available, 90);
  });
}
