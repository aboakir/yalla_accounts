import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/features/finance/services/financial_void_service.dart';
import 'package:yalla_accounts/features/inventory/services/canonical_inventory_service.dart';
import 'package:yalla_accounts/features/inventory/services/inventory_operations_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('Stage 4 inventory financial hard gate', () async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('inventory_stage4_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'inventory.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'inventory-stage4-owner');

    try {
      await PartyFinancialService.createParty(
        name: 'Inventory Supplier',
        phone: '0599555000',
        address: 'Bethlehem',
        customer: false,
        supplier: true,
        database: db,
      );
      final supplierId = (await db.query(
        'suppliers',
        columns: const ['id'],
        where: 'name=?',
        whereArgs: const ['Inventory Supplier'],
        limit: 1,
      ))
          .single['id'] as int;

      final client = await db.insert(
        'clients',
        {'name': 'Inventory Client', 'type': 'individual'},
      );
      await VehicleService.upsertFromRepairOn(
        db,
        number: 'INV-2026',
        type: 'Car',
        model: '2026',
        clientId: client,
      );
      await db.insert('repairs', {
        'id': 'INV-R1',
        'client_id': client,
        'vehicleNumber': 'INV-2026',
        'vehicleType': 'Car',
        'vehicleModel': '2026',
        'fileValue': 1000.0,
        'notes': '',
        'paymentType': 'credit',
        'status': 'DRAFT',
      });
      await db.insert('repair_lines', {
        'id': 'INV-R1-L1',
        'repair_id': 'INV-R1',
        'name': 'Repair work',
        'price': 1000.0,
        'line_type': 'work',
        'qty': 1.0,
        'total': 1000.0,
      });
      await db.transaction(
        (tx) => RepairAutoAccountingService.finalizeNewRepairOn(tx, 'INV-R1'),
      );

      final itemId = await CanonicalInventoryService.createItem(
        name: 'Primer',
        itemKind: 'RAW_MATERIAL',
        unit: 'liter',
        sku: 'PRIMER-A',
        category: 'PAINT',
      );
      final similarId = await CanonicalInventoryService.createItem(
        name: 'Primer',
        itemKind: 'RAW_MATERIAL',
        unit: 'liter',
        sku: 'PRIMER-B',
        category: 'PAINT',
      );
      expect(similarId, isNot(itemId));

      final warehouseId = await CanonicalInventoryService.createWarehouse(
        code: 'MAIN',
        name: 'Main Warehouse',
      );
      await InventoryOperationsService.setUnitConversion(
        itemId: itemId,
        unit: 'can',
        factorToBase: 4,
      );
      expect(
        await InventoryOperationsService.convertToBase(
          itemId: itemId,
          quantity: 5,
          unit: 'can',
        ),
        20,
      );

      await PurchaseInvoiceService.createInvoice(
        id: 'INV-P1',
        supplierId: supplierId,
        date: DateTime(2026, 9, 1),
        note: '100 liters @ 10',
        purchaseType: 'RAW',
        method: 'credit',
        items: [
          {
            'item_name': 'Primer',
            'qty': 100.0,
            'price': 10.0,
            'inventory_item_id': itemId,
            'warehouse_id': warehouseId,
            'unit': 'liter',
            'receive_stock': true,
          },
        ],
      );
      await PurchaseInvoiceService.createInvoice(
        id: 'INV-P2',
        supplierId: supplierId,
        date: DateTime(2026, 9, 2),
        note: '50 liters @ 20',
        purchaseType: 'RAW',
        method: 'credit',
        items: [
          {
            'item_name': 'Primer',
            'qty': 50.0,
            'price': 20.0,
            'inventory_item_id': itemId,
            'warehouse_id': warehouseId,
            'unit': 'liter',
            'receive_stock': true,
          },
        ],
      );

      var valuation = await InventoryOperationsService.valuation(
        itemId: itemId,
        warehouseId: warehouseId,
      );
      expect(valuation.onHand, closeTo(150, 0.001));
      expect(valuation.stockValue, closeTo(2000, 0.01));
      expect(valuation.averageUnitCost, closeTo(13.333333, 0.001));

      final failedBefore = valuation;
      await expectLater(
        InventoryOperationsService.issueToRepair(
          operationId: 'INV-FAIL-1',
          repairId: 'INV-R1',
          itemId: itemId,
          warehouseId: warehouseId,
          quantity: 10,
          costType: RepairCostType.rawMaterial,
          faultAfterMovementForTesting: true,
        ),
        throwsStateError,
      );
      valuation = await InventoryOperationsService.valuation(
        itemId: itemId,
        warehouseId: warehouseId,
      );
      expect(valuation.onHand, failedBefore.onHand);
      expect(valuation.stockValue, failedBefore.stockValue);
      expect(
        await db.query(
          'repair_cost_entries',
          where: 'source_id=?',
          whereArgs: ['INV-FAIL-1'],
        ),
        isEmpty,
      );

      final issue = await InventoryOperationsService.issueToRepair(
        operationId: 'INV-ISSUE-1',
        repairId: 'INV-R1',
        itemId: itemId,
        warehouseId: warehouseId,
        quantity: 30,
        costType: RepairCostType.rawMaterial,
      );
      final retry = await InventoryOperationsService.issueToRepair(
        operationId: 'INV-ISSUE-1',
        repairId: 'INV-R1',
        itemId: itemId,
        warehouseId: warehouseId,
        quantity: 30,
        costType: RepairCostType.rawMaterial,
      );
      expect(retry.issueId, issue.issueId);

      valuation = await InventoryOperationsService.valuation(
        itemId: itemId,
        warehouseId: warehouseId,
      );
      expect(valuation.onHand, closeTo(120, 0.001));
      expect(valuation.stockValue, closeTo(1600, 0.02));

      await expectLater(
        InventoryOperationsService.issueToRepair(
          operationId: 'INV-OVER',
          repairId: 'INV-R1',
          itemId: itemId,
          warehouseId: warehouseId,
          quantity: 500,
          costType: RepairCostType.rawMaterial,
        ),
        throwsStateError,
      );

      await InventoryOperationsService.returnFromRepair(
        operationId: 'INV-RETURN-1',
        issueId: issue.issueId,
        quantity: 5,
      );
      valuation = await InventoryOperationsService.valuation(
        itemId: itemId,
        warehouseId: warehouseId,
      );
      expect(valuation.onHand, closeTo(125, 0.001));

      await InventoryOperationsService.damageStock(
        operationId: 'INV-DAMAGE-1',
        itemId: itemId,
        warehouseId: warehouseId,
        quantity: 5,
        reason: 'Damaged can',
      );
      await InventoryOperationsService.adjustToCount(
        operationId: 'INV-COUNT-UP',
        itemId: itemId,
        warehouseId: warehouseId,
        countedOnHand: 125,
        reason: 'Count surplus',
      );
      await InventoryOperationsService.adjustToCount(
        operationId: 'INV-COUNT-DOWN',
        itemId: itemId,
        warehouseId: warehouseId,
        countedOnHand: 123,
        reason: 'Count shortage',
      );

      await InventoryOperationsService.setReorderLevel(
        itemId: itemId,
        warehouseId: warehouseId,
        level: 125,
      );
      final reorder = await InventoryOperationsService.reorderStatus(
        itemId: itemId,
        warehouseId: warehouseId,
      );
      expect(reorder.needsReorder, isTrue);
      expect(reorder.onHand, closeTo(123, 0.001));

      valuation = await InventoryOperationsService.valuation(
        itemId: itemId,
        warehouseId: warehouseId,
      );
      final card = await InventoryOperationsService.stockCard(
        itemId: itemId,
        warehouseId: warehouseId,
      );
      expect(card.last.runningOnHand, closeTo(123, 0.001));
      expect(card.last.runningValue, closeTo(valuation.stockValue, 0.02));

      final snapshot = await RepairCostService.loadSnapshot(
        'INV-R1',
        executor: db,
      );
      expect(snapshot.directCost, closeTo(333.33, 0.05));
      expect(snapshot.profit, closeTo(666.67, 0.05));

      Future<double> accountNet(String code) async {
        final rows = await db.rawQuery(
          'SELECT COALESCE(SUM(l.debit-l.credit),0) n '
          'FROM gl_lines l JOIN accounts a ON a.id=l.account_id '
          'WHERE a.code=?',
          [code],
        );
        return (rows.single['n'] as num).toDouble();
      }

      expect(
        await accountNet('1400'),
        closeTo(valuation.stockValue, 0.05),
      );
      expect(
        await accountNet('5310'),
        closeTo(snapshot.directCost, 0.05),
      );
      final voidItemId = await CanonicalInventoryService.createItem(
        name: 'Voidable stock',
        itemKind: 'RAW_MATERIAL',
        unit: 'liter',
        sku: 'VOID-STOCK',
      );
      await PurchaseInvoiceService.createInvoice(
        id: 'INV-VOID-PURCHASE',
        supplierId: supplierId,
        date: DateTime(2026, 9, 3),
        note: 'Void stock-managed purchase',
        purchaseType: 'RAW',
        method: 'credit',
        items: [
          {
            'item_name': 'Voidable stock',
            'qty': 10.0,
            'price': 7.0,
            'inventory_item_id': voidItemId,
            'warehouse_id': warehouseId,
            'unit': 'liter',
            'receive_stock': true,
          },
        ],
      );
      expect(
        (await InventoryOperationsService.valuation(
          itemId: voidItemId,
          warehouseId: warehouseId,
        ))
            .onHand,
        10,
      );
      await FinancialVoidService.voidInvoice(
        'INV-VOID-PURCHASE',
        purchase: true,
        reason: 'Test purchase cancellation',
        database: db,
      );
      final voidValuation = await InventoryOperationsService.valuation(
        itemId: voidItemId,
        warehouseId: warehouseId,
      );
      expect(voidValuation.onHand, 0);
      expect(voidValuation.stockValue, 0);
      final voidCard = await InventoryOperationsService.stockCard(
        itemId: voidItemId,
        warehouseId: warehouseId,
      );
      expect(
        voidCard.map((e) => e.movementType),
        containsAll(['PURCHASE_RECEIPT', 'REVERSAL']),
      );

      final consumedItemId = await CanonicalInventoryService.createItem(
        name: 'Consumed stock',
        itemKind: 'RAW_MATERIAL',
        unit: 'liter',
        sku: 'CONSUMED-STOCK',
      );
      await PurchaseInvoiceService.createInvoice(
        id: 'INV-CONSUMED-PURCHASE',
        supplierId: supplierId,
        date: DateTime(2026, 9, 4),
        note: 'Consumed stock-managed purchase',
        purchaseType: 'RAW',
        method: 'credit',
        items: [
          {
            'item_name': 'Consumed stock',
            'qty': 5.0,
            'price': 2.0,
            'inventory_item_id': consumedItemId,
            'warehouse_id': warehouseId,
            'unit': 'liter',
            'receive_stock': true,
          },
        ],
      );
      await InventoryOperationsService.issueToRepair(
        operationId: 'INV-CONSUMED-ISSUE',
        repairId: 'INV-R1',
        itemId: consumedItemId,
        warehouseId: warehouseId,
        quantity: 5,
        costType: RepairCostType.rawMaterial,
      );
      await expectLater(
        FinancialVoidService.voidInvoice(
          'INV-CONSUMED-PURCHASE',
          purchase: true,
          reason: 'Must fail while consumed',
          database: db,
        ),
        throwsStateError,
      );
      expect(
        (await db.query(
          'purchase_invoices',
          columns: const ['status'],
          where: 'id=?',
          whereArgs: ['INV-CONSUMED-PURCHASE'],
        ))
            .single['status'],
        isNot('VOID'),
      );

      final unbalanced = await db.rawQuery(
        'SELECT entry_id FROM gl_lines GROUP BY entry_id '
        'HAVING ABS(SUM(debit-credit)) > 0.001',
      );
      expect(unbalanced, isEmpty);
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}
