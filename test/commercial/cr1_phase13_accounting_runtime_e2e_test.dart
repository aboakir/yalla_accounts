import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  sq.databaseFactory = databaseFactoryFfi;

  test(
    'Phase 13 accounting journey survives suspend/read-only/reactivate',
    () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp(
        'cr1_phase13_accounting_',
      );
      final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db',
      );
      final session = await startAccountingSession(db, 'phase13-accountant');
      try {
        Future<void> runtime(String mode, String reason) => db
            .update(
                LicenseRuntimeTables.table,
                {
                  'mode': mode,
                  'reason': reason,
                  'source': 'SERVER_LIFECYCLE',
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                },
                where: 'singleton_id=1')
            .then((_) {});

        await runtime(
          LicenseRuntimeMode.writable,
          'Phase 13 active subscription',
        );
        final client = await db.insert('clients', {
          'name': 'Phase 13 Customer',
          'type': 'individual',
        });
        final supplier = await db.insert('suppliers', {
          'name': 'Phase 13 Supplier',
        });
        final cash = (await db.query(
          'accounts',
          where: 'code=?',
          whereArgs: ['1000'],
        ))
            .single['id'];
        final revenue = (await db.query(
          'accounts',
          where: 'code=?',
          whereArgs: ['4000'],
        ))
            .single['id'];
        final ar = await db.insert('accounts', {
          'code': '1200.P13.$client',
          'name': 'Phase 13 AR',
          'type': 'ASSET',
          'normal_balance': 'DEBIT',
        });
        final ap = await db.insert('accounts', {
          'code': '2200.P13.${supplier.toString().padLeft(4, '0')}',
          'name': 'Phase 13 AP',
          'type': 'LIABILITY',
          'normal_balance': 'CREDIT',
        });
        final expense = await db.insert('accounts', {
          'code': '5300.P13',
          'name': 'Phase 13 Direct Cost',
          'type': 'EXPENSE',
          'normal_balance': 'DEBIT',
        });
        await db.update(
          'clients',
          {'account_id': ar},
          where: 'id=?',
          whereArgs: [client],
        );

        const repairId = 'P13-REPAIR-1';
        const purchaseId = 'P13-PURCHASE-1';
        const purchaseLineId = 'P13-PURCHASE-LINE-1';
        const invoiceId = 'P13-INVOICE-1';
        await db.insert('repairs', {
          'id': repairId,
          'client_id': client,
          'fileValue': 1500.0,
          'status': 'APPROVED',
        });
        await db.insert('purchase_invoices', {
          'id': purchaseId,
          'supplier_id': supplier,
          'amount_total': 400.0,
          'date': '2026-09-17',
          'status': 'UNPAID',
        });
        await db.insert('purchase_invoice_lines', {
          'id': purchaseLineId,
          'invoice_id': purchaseId,
          'item_name': 'Phase 13 Part',
          'qty': 2.0,
          'unit_price': 200.0,
          'price': 200.0,
          'total': 400.0,
          'category': 'PARTS',
        });
        await AccountingTables.postEntryGLOn(
          ex: db,
          date: DateTime(2026, 9, 17),
          source: 'PURCHASE',
          sourceId: purchaseId,
          lines: [
            {'account_id': expense, 'debit': 400.0, 'credit': 0.0},
            {
              'account_id': ap,
              'debit': 0.0,
              'credit': 400.0,
              'party_type': 'SUPPLIER',
              'party_id': supplier,
            },
          ],
        );
        await RepairCostService.allocatePurchaseLine(
          repairId: repairId,
          purchaseLineId: purchaseLineId,
          costType: RepairCostType.parts,
          quantityUsed: 1,
          actorId: 'phase13-accountant',
          executor: db,
        );
        await RepairCostService.addManualCost(
          repairId: repairId,
          costType: RepairCostType.labor,
          itemName: 'Phase 13 Labor',
          quantityUsed: 2,
          workHours: 2,
          unitCost: 50,
          actorId: 'phase13-accountant',
          executor: db,
        );

        await db.insert('invoices', {
          'id': invoiceId,
          'repair_id': repairId,
          'client_id': client,
          'date': '2026-09-17',
          'total': 1500.0,
          'status': 'UNPAID',
        });
        await AccountingTables.postEntryGLOn(
          ex: db,
          date: DateTime(2026, 9, 17),
          source: 'INVOICE',
          sourceId: invoiceId,
          lines: [
            {
              'account_id': ar,
              'debit': 1500.0,
              'credit': 0.0,
              'party_type': 'CLIENT',
              'party_id': client,
              'repair_id': repairId,
              'invoice_id': invoiceId,
            },
            {
              'account_id': revenue,
              'debit': 0.0,
              'credit': 1500.0,
              'repair_id': repairId,
              'invoice_id': invoiceId,
            },
          ],
        );

        final receipt = await PaymentService.insertCanonicalReceipt(
          operationId: 'P13-RECEIPT-1',
          database: db,
          clientId: client,
          customerName: 'Phase 13 Customer',
          method: 'cash',
          date: DateTime(2026, 9, 17),
          allocations: const [
            ReceiptAllocationInput(repairId: repairId, amount: 600),
          ],
          unallocatedAmount: 0,
        );
        final truth = await RepairFinancialTruthService.load(
          repairId,
          executor: db,
        );
        expect(truth.fileValue, 1500.0);
        expect(truth.paid, 600.0);
        expect(truth.remaining, 900.0);
        expect(truth.customerArBalance, 900.0);

        final parties = await PartyFinancialService.balances(executor: db);
        expect(
          parties
              .singleWhere((p) => p.customerLegacyId == '$client')
              .receivableBalance,
          900.0,
        );
        expect(
          parties
              .singleWhere((p) => p.supplierLegacyId == '$supplier')
              .payableBalance,
          400.0,
        );
        final profit = await RepairCostService.loadSnapshot(
          repairId,
          executor: db,
        );
        expect(profit.revenue, 1500.0);
        expect(profit.directCost, 300.0);
        expect(profit.profit, 1200.0);

        final totals = (await db.rawQuery(
          'SELECT COALESCE(SUM(debit),0) d,COALESCE(SUM(credit),0) c FROM gl_lines',
        ))
            .single;
        expect(
          (totals['d'] as num).toDouble(),
          (totals['c'] as num).toDouble(),
        );
        final cashBalance = ((await db.rawQuery(
          'SELECT COALESCE(SUM(debit-credit),0) n FROM gl_lines WHERE account_id=?',
          [cash],
        ))
                .single['n'] as num)
            .toDouble();
        expect(cashBalance, 600.0);
        expect(receipt.receiptNumber, greaterThan(0));
        final beforeCounts = {
          'gl': (await db.rawQuery(
            'SELECT COUNT(*) n FROM gl_entries',
          ))
              .single['n'],
          'receipts': (await db.rawQuery(
            'SELECT COUNT(*) n FROM receipt_headers',
          ))
              .single['n'],
          'repairs': (await db.rawQuery(
            'SELECT COUNT(*) n FROM repairs',
          ))
              .single['n'],
        };
        await runtime(
          LicenseRuntimeMode.readOnlySuspended,
          'Phase 13 subscription suspended by Control',
        );
        expect(
          (await db.query(
            'repairs',
            where: 'id=?',
            whereArgs: [repairId],
          ))
              .length,
          1,
        );
        final readOnlyTruth = await RepairFinancialTruthService.load(
          repairId,
          executor: db,
        );
        expect(readOnlyTruth.customerArBalance, 900.0);
        expect(
          (await RepairCostService.loadSnapshot(repairId, executor: db)).profit,
          1200.0,
        );

        await expectLater(
          db.insert('repairs', {
            'id': 'P13-BLOCKED-REPAIR',
            'client_id': client,
            'fileValue': 1.0,
            'status': 'APPROVED',
          }),
          throwsA(isA<sq.DatabaseException>()),
        );
        await expectLater(
          PaymentService.insertCanonicalReceipt(
            operationId: 'P13-BLOCKED-RECEIPT',
            database: db,
            clientId: client,
            customerName: 'Phase 13 Customer',
            method: 'cash',
            date: DateTime(2026, 9, 17),
            allocations: const [
              ReceiptAllocationInput(repairId: repairId, amount: 100),
            ],
            unallocatedAmount: 0,
          ),
          throwsA(isA<sq.DatabaseException>()),
        );
        expect(
          (await db.rawQuery('SELECT COUNT(*) n FROM gl_entries')).single['n'],
          beforeCounts['gl'],
        );
        expect(
          (await db.rawQuery(
            'SELECT COUNT(*) n FROM receipt_headers',
          ))
              .single['n'],
          beforeCounts['receipts'],
        );
        expect(
          (await db.rawQuery('SELECT COUNT(*) n FROM repairs')).single['n'],
          beforeCounts['repairs'],
        );

        await runtime(
          LicenseRuntimeMode.writable,
          'Phase 13 subscription reactivated by Control',
        );
        final resumed = await PaymentService.insertCanonicalReceipt(
          operationId: 'P13-RECEIPT-2',
          database: db,
          clientId: client,
          customerName: 'Phase 13 Customer',
          method: 'cash',
          date: DateTime(2026, 9, 17),
          allocations: const [
            ReceiptAllocationInput(repairId: repairId, amount: 100),
          ],
          unallocatedAmount: 0,
        );
        expect(resumed.receiptNumber, isNot(receipt.receiptNumber));
        final resumedTruth = await RepairFinancialTruthService.load(
          repairId,
          executor: db,
        );
        expect(resumedTruth.paid, 700.0);
        expect(resumedTruth.remaining, 800.0);
        expect(
          (await PartyFinancialService.balances(executor: db))
              .singleWhere((p) => p.customerLegacyId == '$client')
              .receivableBalance,
          800.0,
        );
        expect(
          (await RepairCostService.loadSnapshot(repairId, executor: db)).profit,
          1200.0,
        );
        final receiptAudit = await db.query(
          'app_audit_events',
          where: 'action=?',
          whereArgs: ['RECEIPT_POSTED'],
        );
        expect(receiptAudit.length, greaterThanOrEqualTo(2));
        expect(
          receiptAudit.every(
            (row) => row['actor_user_id'] == 'phase13-accountant',
          ),
          isTrue,
        );
      } finally {
        await session.endEphemeralPreviewSession();
        if (db.isOpen) await db.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
