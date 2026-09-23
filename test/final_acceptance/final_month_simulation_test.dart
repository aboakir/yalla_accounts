import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/accounting_gl.dart';
import 'package:yalla_accounts/core/services/accounting_integrity_service.dart';
import 'package:yalla_accounts/core/services/accounting_period_service.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/supplier_payment_service.dart';
import 'package:yalla_accounts/features/finance/services/financial_overview_service.dart';
import 'package:yalla_accounts/features/inventory/services/canonical_inventory_service.dart';
import 'package:yalla_accounts/features/inventory/services/inventory_operations_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('final commercial month simulation reconciles and survives period close',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('final_month_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'month.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'final-month-owner');

    Future<double> accountBalance(String code) async {
      final row = (await db.rawQuery(
        'SELECT COALESCE(SUM(l.debit-l.credit),0) n '
        'FROM gl_lines l JOIN accounts a ON a.id=l.account_id '
        'WHERE a.code=? OR a.code LIKE ?',
        [code, '$code.%'],
      ))
          .single;
      return (row['n'] as num).toDouble();
    }

    Map<String, dynamic> chequeDraft(String key, double amount) => {
          'uuid': 'uuid-$key',
          'instrument_key': key,
          'cheque_no': 'NO-$key',
          'drawer_name': 'Final Customer',
          'bank_name': 'Palestine Bank',
          'bank_branch': 'Bethlehem',
          'issue_date': '2026-09-20T00:00:00',
          'due_date': '2026-10-20T00:00:00',
          'amount': amount,
        };

    try {
      await PartyFinancialService.createParty(
        name: 'Final Customer',
        phone: '0599001111',
        address: 'Bethlehem',
        customer: true,
        supplier: false,
        database: db,
      );
      await PartyFinancialService.createParty(
        name: 'Final Supplier',
        phone: '0599002222',
        address: 'Bethlehem',
        customer: false,
        supplier: true,
        database: db,
      );
      final clientId = (await db.query(
        'clients',
        columns: const ['id'],
        where: 'name=?',
        whereArgs: const ['Final Customer'],
        limit: 1,
      ))
          .single['id'] as int;
      final supplierId = (await db.query(
        'suppliers',
        columns: const ['id'],
        where: 'name=?',
        whereArgs: const ['Final Supplier'],
        limit: 1,
      ))
          .single['id'] as int;

      await db.insert('repairs', {
        'id': 'FINAL-R1',
        'client_id': clientId,
        'fileValue': 5000.0,
        'notes': 'Final month simulation',
        'paymentType': 'credit',
        'status': 'DRAFT',
        'receivedDate': '2026-09-02T09:00:00',
        'beneficiaryName': 'Final Customer',
        'beneficiaryType': 'أفراد',
        'vehicleNumber': 'FINAL-001',
        'vehicleType': 'Sedan',
        'vehicleModel': '2026',
      });
      await db.insert('repair_lines', {
        'id': 'FINAL-R1-WORK',
        'repair_id': 'FINAL-R1',
        'line_type': 'work',
        'name': 'Body and paint work',
        'qty': 1.0,
        'price': 5000.0,
        'total': 5000.0,
      });
      await db.transaction(
        (tx) => RepairAutoAccountingService.finalizeNewRepairOn(tx, 'FINAL-R1'),
      );

      final itemId = await CanonicalInventoryService.createItem(
        name: 'Final Primer',
        itemKind: 'RAW_MATERIAL',
        unit: 'liter',
        sku: 'FINAL-PRIMER',
        category: 'PAINT',
      );
      final warehouseId = await CanonicalInventoryService.createWarehouse(
        code: 'FINAL-MAIN',
        name: 'Final Main Warehouse',
      );
      await PurchaseInvoiceService.createInvoice(
        id: 'FINAL-P1',
        supplierId: supplierId,
        date: DateTime(2026, 9, 3),
        note: '100 liters @ 20',
        purchaseType: 'RAW',
        method: 'credit',
        items: [
          {
            'item_name': 'Final Primer',
            'qty': 100.0,
            'price': 20.0,
            'inventory_item_id': itemId,
            'warehouse_id': warehouseId,
            'unit': 'liter',
            'receive_stock': true,
          },
        ],
      );
      await InventoryOperationsService.issueToRepair(
        operationId: 'FINAL-ISSUE-1',
        repairId: 'FINAL-R1',
        itemId: itemId,
        warehouseId: warehouseId,
        quantity: 30,
        costType: RepairCostType.rawMaterial,
      );

      await PaymentService.insertCanonicalReceipt(
        operationId: 'FINAL-CASH-1',
        database: db,
        clientId: clientId,
        customerName: 'Final Customer',
        method: 'cash',
        date: DateTime(2026, 9, 10),
        allocations: const [
          ReceiptAllocationInput(
            repairId: 'FINAL-R1',
            amount: 1500,
            paymentId: 'FINAL-CASH-R1',
          ),
        ],
      );
      await PaymentService.insertCanonicalReceipt(
        operationId: 'FINAL-BANK-1',
        database: db,
        clientId: clientId,
        customerName: 'Final Customer',
        method: 'bank',
        date: DateTime(2026, 9, 15),
        allocations: const [
          ReceiptAllocationInput(
            repairId: 'FINAL-R1',
            amount: 1000,
            paymentId: 'FINAL-BANK-R1',
          ),
        ],
      );
      await PaymentService.insertCanonicalReceipt(
        operationId: 'FINAL-CHEQUE-1',
        database: db,
        clientId: clientId,
        customerName: 'Final Customer',
        method: 'cheque',
        date: DateTime(2026, 9, 20),
        allocations: const [
          ReceiptAllocationInput(
            repairId: 'FINAL-R1',
            amount: 500,
            paymentId: 'FINAL-CHEQUE-R1',
          ),
        ],
        chequeDraft: chequeDraft('FINAL-CHEQUE-1', 500),
      );

      await SupplierPaymentService.insertAndPost(
        operationId: 'FINAL-SP-1',
        supplierId: supplierId,
        amount: 800,
        date: DateTime(2026, 9, 25),
        method: 'cash',
        note: 'September supplier payment',
        database: db,
      );

      await EmployeeDatabaseService.insert(Employee.fromMap({
        'id': 'FINAL-E1',
        'employee_code': 'FINAL-E1',
        'full_name': 'Final Employee',
        'hire_date': '2026-01-01',
        'created_at': '2026-01-01',
        'status': 'active',
        'base_salary': 1000.0,
        'contract_type': 'monthly',
      }));
      final payrollRun = await PayrollDatabaseService.accrue(
        employeeId: 'FINAL-E1',
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        accrualDate: DateTime(2026, 9, 30),
        gross: 1000,
        note: 'September payroll',
      );
      await PayrollDatabaseService.pay(
        runId: payrollRun,
        amount: 600,
        date: DateTime(2026, 9, 30),
        method: 'cash',
      );

      await AccountingIntegrityService.assertHealthyOn(db);

      final overview = await FinancialOverviewService.loadOn(
        db,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );
      expect(overview.cashBalance, closeTo(100, 0.01));
      expect(overview.bankBalance, closeTo(1000, 0.01));
      expect(overview.customerReceivables, closeTo(2000, 0.01));
      expect(overview.supplierPayables, closeTo(1200, 0.01));
      expect(overview.payrollPayables, closeTo(400, 0.01));
      expect(overview.revenue, closeTo(5000, 0.01));
      expect(overview.expenses, closeTo(1600, 0.01));
      expect(overview.netProfit, closeTo(3400, 0.01));
      expect(overview.periodBalanced, isTrue);
      expect(overview.accountingHealthy, isTrue);

      expect(await accountBalance('1020'), closeTo(500, 0.01));
      expect(await accountBalance('1400'), closeTo(1400, 0.01));
      expect(await accountBalance('5310'), closeTo(600, 0.01));
      expect(await accountBalance('5100'), closeTo(1000, 0.01));

      final inventory = await InventoryOperationsService.valuation(
        itemId: itemId,
        warehouseId: warehouseId,
        executor: db,
      );
      expect(inventory.onHand, closeTo(70, 0.001));
      expect(inventory.stockValue, closeTo(1400, 0.01));

      final repair = await RepairCostService.loadSnapshot(
        'FINAL-R1',
        executor: db,
      );
      expect(repair.revenue, closeTo(5000, 0.01));
      expect(repair.directCost, closeTo(600, 0.01));
      expect(repair.profit, closeTo(4400, 0.01));

      final parties = await PartyFinancialService.balances(executor: db);
      expect(
        parties
            .singleWhere((p) => p.customerLegacyId == '$clientId')
            .receivableBalance,
        closeTo(2000, 0.01),
      );
      expect(
        parties
            .singleWhere((p) => p.supplierLegacyId == '$supplierId')
            .payableBalance,
        closeTo(1200, 0.01),
      );

      final trial = await GL.trialBalance(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30, 23, 59, 59),
      );
      expect(trial['balanced'], isTrue);
      expect(
        (trial['total_debit'] as num).toDouble(),
        closeTo((trial['total_credit'] as num).toDouble(), 0.005),
      );

      final closeId = await AccountingPeriodService.closePeriod(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
        note: 'Final September close',
        database: db,
      );
      expect(closeId, greaterThan(0));

      final receiptCountBefore = ((await db.rawQuery(
        'SELECT COUNT(*) n FROM receipt_headers',
      ))
              .single['n'] as num)
          .toInt();
      final purchaseCountBefore = ((await db.rawQuery(
        'SELECT COUNT(*) n FROM purchase_invoices',
      ))
              .single['n'] as num)
          .toInt();
      final payrollCountBefore = ((await db.rawQuery(
        'SELECT COUNT(*) n FROM payroll_runs',
      ))
              .single['n'] as num)
          .toInt();
      final movementCountBefore = ((await db.rawQuery(
        'SELECT COUNT(*) n FROM inventory_movements',
      ))
              .single['n'] as num)
          .toInt();

      await expectLater(
        PaymentService.insertCanonicalReceipt(
          operationId: 'FINAL-BLOCKED-RECEIPT',
          database: db,
          clientId: clientId,
          customerName: 'Final Customer',
          method: 'cash',
          date: DateTime(2026, 9, 30),
          allocations: const [
            ReceiptAllocationInput(
              repairId: 'FINAL-R1',
              amount: 100,
              paymentId: 'FINAL-BLOCKED-R1',
            ),
          ],
        ),
        throwsA(anything),
      );
      expect(
        ((await db.rawQuery(
          'SELECT COUNT(*) n FROM receipt_headers',
        ))
                .single['n'] as num)
            .toInt(),
        receiptCountBefore,
      );

      await expectLater(
        PurchaseInvoiceService.createInvoice(
          id: 'FINAL-BLOCKED-PURCHASE',
          supplierId: supplierId,
          date: DateTime(2026, 9, 29),
          note: 'Must rollback in closed period',
          purchaseType: 'RAW',
          method: 'credit',
          items: [
            {
              'item_name': 'Final Primer',
              'qty': 1.0,
              'price': 20.0,
              'inventory_item_id': itemId,
              'warehouse_id': warehouseId,
              'unit': 'liter',
              'receive_stock': true,
            },
          ],
        ),
        throwsA(anything),
      );
      expect(
        ((await db.rawQuery(
          'SELECT COUNT(*) n FROM purchase_invoices',
        ))
                .single['n'] as num)
            .toInt(),
        purchaseCountBefore,
      );
      expect(
        ((await db.rawQuery(
          'SELECT COUNT(*) n FROM inventory_movements',
        ))
                .single['n'] as num)
            .toInt(),
        movementCountBefore,
      );

      await EmployeeDatabaseService.insert(Employee.fromMap({
        'id': 'FINAL-E2',
        'employee_code': 'FINAL-E2',
        'full_name': 'Blocked Employee',
        'hire_date': '2026-01-01',
        'created_at': '2026-01-01',
        'status': 'active',
        'base_salary': 500.0,
        'contract_type': 'monthly',
      }));
      await expectLater(
        PayrollDatabaseService.accrue(
          employeeId: 'FINAL-E2',
          periodStart: DateTime(2026, 9, 1),
          periodEnd: DateTime(2026, 9, 30),
          accrualDate: DateTime(2026, 9, 30),
          gross: 500,
        ),
        throwsA(anything),
      );
      expect(
        ((await db.rawQuery(
          'SELECT COUNT(*) n FROM payroll_runs',
        ))
                .single['n'] as num)
            .toInt(),
        payrollCountBefore,
      );

      final inventoryBeforeDamage = await InventoryOperationsService.valuation(
        itemId: itemId,
        warehouseId: warehouseId,
        executor: db,
      );
      await expectLater(
        InventoryOperationsService.damageStock(
          operationId: 'FINAL-BLOCKED-DAMAGE',
          itemId: itemId,
          warehouseId: warehouseId,
          quantity: 1,
          reason: 'Closed-period block proof',
        ),
        throwsA(anything),
      );
      final inventoryAfterDamage = await InventoryOperationsService.valuation(
        itemId: itemId,
        warehouseId: warehouseId,
        executor: db,
      );
      expect(inventoryAfterDamage.onHand, inventoryBeforeDamage.onHand);
      expect(inventoryAfterDamage.stockValue, inventoryBeforeDamage.stockValue);

      await AccountingIntegrityService.assertHealthyOn(db);
      final finalOverview = await FinancialOverviewService.loadOn(
        db,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );
      expect(finalOverview.cashBalance, overview.cashBalance);
      expect(finalOverview.bankBalance, overview.bankBalance);
      expect(finalOverview.customerReceivables, overview.customerReceivables);
      expect(finalOverview.supplierPayables, overview.supplierPayables);
      expect(finalOverview.payrollPayables, overview.payrollPayables);
      expect(finalOverview.netProfit, overview.netProfit);
      expect(finalOverview.periodBalanced, isTrue);
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}
