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

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<int> createSupplier(Database db, String name) async {
    await PartyFinancialService.createParty(
      name: name,
      phone: '0599000000',
      address: 'Bethlehem',
      customer: false,
      supplier: true,
      database: db,
    );
    final rows = await db.query(
      'suppliers',
      columns: const ['id'],
      where: 'name=?',
      whereArgs: [name],
      limit: 1,
    );
    return (rows.single['id'] as num).toInt();
  }

  Future<({int itemId, int warehouseId})> createStockMaster() async {
    final itemId = await CanonicalInventoryService.createItem(
      name: 'Void Test Primer',
      itemKind: 'RAW_MATERIAL',
      unit: 'liter',
      sku: 'VOID-PRIMER',
      category: 'PAINT',
    );
    final warehouseId = await CanonicalInventoryService.createWarehouse(
      code: 'VOID',
      name: 'Void Test Warehouse',
    );
    return (itemId: itemId, warehouseId: warehouseId);
  }

  test('purchase void reverses stock and GL exactly once', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('inventory_void_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'void.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'inventory-void-owner');
    try {
      final supplierId = await createSupplier(db, 'Void Supplier');
      final master = await createStockMaster();
      const invoiceId = 'VOID-PURCHASE-1';
      await PurchaseInvoiceService.createInvoice(
        id: invoiceId,
        supplierId: supplierId,
        date: DateTime(2026, 9, 23),
        note: 'Stock receipt to be voided',
        purchaseType: 'RAW',
        method: 'credit',
        items: [
          {
            'item_name': 'Void Test Primer',
            'qty': 10.0,
            'price': 5.0,
            'inventory_item_id': master.itemId,
            'warehouse_id': master.warehouseId,
            'unit': 'liter',
            'receive_stock': true,
          },
        ],
      );
      var valuation = await InventoryOperationsService.valuation(
        itemId: master.itemId,
        warehouseId: master.warehouseId,
        executor: db,
      );
      expect(valuation.onHand, closeTo(10, 0.001));
      expect(valuation.stockValue, closeTo(50, 0.01));

      expect(
        await FinancialVoidService.voidInvoice(
          invoiceId,
          purchase: true,
          reason: 'QA purchase void',
          database: db,
        ),
        1,
      );

      valuation = await InventoryOperationsService.valuation(
        itemId: master.itemId,
        warehouseId: master.warehouseId,
        executor: db,
      );
      expect(valuation.onHand, closeTo(0, 0.001));
      expect(valuation.stockValue, closeTo(0, 0.01));

      final invoice = (await db.query(
        'purchase_invoices',
        where: 'id=?',
        whereArgs: [invoiceId],
      ))
          .single;
      expect(invoice['status'], 'VOID');

      final reversals = await db.query(
        'inventory_movements',
        where: 'source_entity_type=? AND source_reference=?',
        whereArgs: ['PURCHASE_RECEIPT_VOID', invoiceId],
      );
      // Reversal references the purchase line id, not the header id.
      final allVoidMovements = await db.query(
        'inventory_movements',
        where: 'source_entity_type=?',
        whereArgs: ['PURCHASE_RECEIPT_VOID'],
      );
      expect(reversals, isEmpty);
      expect(allVoidMovements, hasLength(1));

      final unbalanced = await db.rawQuery(
        'SELECT entry_id FROM gl_lines GROUP BY entry_id '
        'HAVING ABS(SUM(debit-credit)) > 0.001',
      );
      expect(unbalanced, isEmpty);

      expect(
        await FinancialVoidService.voidInvoice(
          invoiceId,
          purchase: true,
          reason: 'QA duplicate void',
          database: db,
        ),
        0,
      );
      expect(
        await db.query(
          'inventory_movements',
          where: 'source_entity_type=?',
          whereArgs: ['PURCHASE_RECEIPT_VOID'],
        ),
        hasLength(1),
      );
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  test('purchase void is rejected after received stock is consumed', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('inventory_void_used_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'used.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);
    final session =
        await startAccountingSession(db, 'inventory-void-used-owner');
    try {
      final supplierId = await createSupplier(db, 'Consumed Stock Supplier');
      final master = await createStockMaster();
      const invoiceId = 'VOID-PURCHASE-USED';
      await PurchaseInvoiceService.createInvoice(
        id: invoiceId,
        supplierId: supplierId,
        date: DateTime(2026, 9, 23),
        note: 'Stock that will be consumed',
        purchaseType: 'RAW',
        method: 'credit',
        items: [
          {
            'item_name': 'Void Test Primer',
            'qty': 10.0,
            'price': 5.0,
            'inventory_item_id': master.itemId,
            'warehouse_id': master.warehouseId,
            'unit': 'liter',
            'receive_stock': true,
          },
        ],
      );

      await CanonicalInventoryService.recordMovement(
        itemId: master.itemId,
        warehouseId: master.warehouseId,
        movementType: 'SALE',
        onHandDelta: -2,
        unitCost: 5,
        landedCost: 5,
        sourceEntityType: 'QA_CONSUMPTION',
        sourceReference: 'QA-CONSUME-1',
      );

      await expectLater(
        FinancialVoidService.voidInvoice(
          invoiceId,
          purchase: true,
          reason: 'Must fail because stock was consumed',
          database: db,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'INVENTORY_PURCHASE_VOID_STOCK_ALREADY_CONSUMED',
          ),
        ),
      );

      final invoice = (await db.query(
        'purchase_invoices',
        where: 'id=?',
        whereArgs: [invoiceId],
      ))
          .single;
      expect(invoice['status'], isNot('VOID'));
      expect(
        await db.query(
          'inventory_movements',
          where: 'source_entity_type=?',
          whereArgs: ['PURCHASE_RECEIPT_VOID'],
        ),
        isEmpty,
      );
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}
