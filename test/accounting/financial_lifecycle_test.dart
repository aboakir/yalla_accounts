import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_payment_service.dart';
import 'package:yalla_accounts/features/finance/services/financial_void_service.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'receipt and supplier lifecycle preserve balances, identity and atomic audit',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('financial_lifecycle_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    final session = await startAccountingSession(db, 'accountant');
    try {
      final client = await db
          .insert('clients', {'name': 'Customer', 'type': 'individual'});
      final supplier = await db.insert('suppliers', {'name': 'Supplier'});
      final cash =
          (await db.query('accounts', where: 'code=?', whereArgs: ['1000']))
              .single['id'];
      final revenue =
          (await db.query('accounts', where: 'code=?', whereArgs: ['4000']))
              .single['id'];
      final ar = await db.insert('accounts', {
        'code': '1200.C$client',
        'name': 'AR',
        'type': 'ASSET',
        'normal_balance': 'DEBIT'
      });
      final ap = await db.insert('accounts', {
        'code': '2200.S${supplier.toString().padLeft(4, '0')}',
        'name': 'AP',
        'type': 'LIABILITY',
        'normal_balance': 'CREDIT'
      });
      await db.update('clients', {'account_id': ar},
          where: 'id=?', whereArgs: [client]);
      Future<double> balance(Object? account) async => ((await db.rawQuery(
                  'SELECT COALESCE(SUM(debit-credit),0) AS n FROM gl_lines WHERE account_id=?',
                  [account]))
              .single['n'] as num)
          .toDouble();
      await AccountingTables.postEntryGLOn(
          ex: db,
          date: DateTime(2026, 9, 8),
          source: 'INVOICE',
          sourceId: 'sale',
          lines: [
            {
              'account_id': ar,
              'debit': 1000.0,
              'credit': 0.0,
              'party_type': 'CLIENT',
              'party_id': client
            },
            {'account_id': revenue, 'debit': 0.0, 'credit': 1000.0}
          ]);
      Future<CanonicalReceiptResult> receive(String operation, double amount) =>
          PaymentService.insertCanonicalReceipt(
              operationId: operation,
              database: db,
              clientId: client,
              customerName: 'Customer',
              method: 'cash',
              date: DateTime(2026, 9, 8),
              allocations: const [],
              unallocatedAmount: amount);
      final receipt = await receive('receipt-one', 300);
      expect(await PaymentService.customerCreditForClient(client, executor: db),
          300);
      expect((await receive('receipt-one', 300)).receiptNumber,
          receipt.receiptNumber);
      await expectLater(receive('receipt-one', 301), throwsStateError);
      expect(await balance(ar), 700);
      expect(await balance(cash), 300);
      for (var i = 0; i < 3; i++) {
        final parties = await PartyFinancialService.balances(executor: db);
        expect(
            parties
                .singleWhere((p) => p.customerLegacyId == '$client')
                .receivableBalance,
            700);
      }
      expect(await balance(ar), 700);
      await PaymentService.reverseReceipt(receipt.receiptNumber,
          reason: 'Receipt correction', database: db);
      expect(await balance(ar), 1000);
      expect(await balance(cash), 0);
      expect(await PaymentService.customerCreditForClient(client, executor: db),
          0);
      await expectLater(
          PaymentService.reverseReceipt(receipt.receiptNumber,
              reason: 'Again', database: db),
          throwsStateError);
      final audit = await db.query('app_audit_events',
          where: 'action=?', whereArgs: ['RECEIPT_REVERSED']);
      expect(audit.length, 1);
      expect(audit.single['actor_user_id'], 'accountant');
      expect(jsonDecode(audit.single['before_json'] as String), isNotEmpty);
      expect(jsonDecode(audit.single['after_json'] as String), isNotEmpty);
      await db.execute(
          "CREATE TRIGGER reject_receipt_audit BEFORE INSERT ON app_audit_events WHEN NEW.action='RECEIPT_POSTED' BEGIN SELECT RAISE(ABORT,'audit unavailable'); END");
      await expectLater(receive('receipt-fail', 100), throwsA(anything));
      expect(await balance(cash), 0);
      expect(
          await db.query('receipt_requests',
              where: 'operation_id=?', whereArgs: ['receipt-fail']),
          isEmpty);
      await db.execute('DROP TRIGGER reject_receipt_audit');
      await db.insert('repairs', {
        'id': 'repair-a',
        'client_id': client,
        'fileValue': 500.0,
        'status': 'APPROVED'
      });
      await db.insert('invoices', {
        'id': 'repair-invoice',
        'repair_id': 'repair-a',
        'client_id': client,
        'date': '2026-09-08',
        'total': 500.0,
        'status': 'UNPAID'
      });
      await AccountingTables.postEntryGLOn(
          ex: db,
          date: DateTime(2026, 9, 8),
          source: 'INVOICE',
          sourceId: 'repair-invoice',
          lines: [
            {
              'account_id': ar,
              'debit': 500.0,
              'credit': 0.0,
              'party_type': 'CLIENT',
              'party_id': client,
              'repair_id': 'repair-a',
              'invoice_id': 'repair-invoice'
            },
            {
              'account_id': revenue,
              'debit': 0.0,
              'credit': 500.0,
              'repair_id': 'repair-a',
              'invoice_id': 'repair-invoice'
            }
          ]);
      final allocated = await PaymentService.insertCanonicalReceipt(
          operationId: 'repair-receipt',
          database: db,
          clientId: client,
          customerName: 'Customer',
          method: 'cash',
          date: DateTime(2026, 9, 8),
          allocations: [
            ReceiptAllocationInput(repairId: 'repair-a', amount: 200)
          ],
          unallocatedAmount: 0);
      expect(
          await RepairFinancialTruthService.paidForRepair('repair-a',
              executor: db),
          200);
      expect(
          await RepairFinancialTruthService.customerArForRepair('repair-a',
              executor: db),
          300);
      await expectLater(
          RepairAutoAccountingService.deleteRepair('repair-a', database: db),
          throwsStateError);
      await PaymentService.reverseReceipt(allocated.receiptNumber,
          reason: 'Correction', database: db);
      expect(
          await RepairFinancialTruthService.paidForRepair('repair-a',
              executor: db),
          0);
      await RepairAutoAccountingService.deleteRepair('repair-a',
          database: db, reason: 'Cancelled repair');
      await RepairAutoAccountingService.deleteRepair('repair-a',
          database: db, reason: 'Retry');
      expect(
          await RepairFinancialTruthService.customerArForRepair('repair-a',
              executor: db),
          0);
      expect(
          (await db.query('invoices',
                  where: 'id=?', whereArgs: ['repair-invoice']))
              .single['total'],
          500);
      expect(
          (await db.query('app_audit_events',
                  where: 'action=?', whereArgs: ['REPAIR_VOIDED']))
              .length,
          1);
      expect(await balance(ar), 1000);
      expect(await balance(cash), 0);
      await expectLater(db.delete('receipt_headers'), throwsA(anything));
      await expectLater(db.delete('receipt_allocations'), throwsA(anything));
      await expectLater(
          db.update('receipt_headers', {'total_amount': 1}), throwsA(anything));
      await db.insert('purchase_invoices', {
        'id': 'purchase',
        'supplier_id': supplier,
        'amount_total': 2000.0,
        'date': '2026-09-08',
        'status': 'UNPAID'
      });
      await AccountingTables.postEntryGLOn(
          ex: db,
          date: DateTime(2026, 9, 8),
          source: 'PURCHASE',
          sourceId: 'purchase',
          lines: [
            {'account_id': revenue, 'debit': 2000.0, 'credit': 0.0},
            {
              'account_id': ap,
              'debit': 0.0,
              'credit': 2000.0,
              'party_type': 'SUPPLIER',
              'party_id': supplier
            }
          ]);
      Future<int> pay() => PurchasePaymentService.payPurchase(
          database: db,
          operationId: 'supplier-pay',
          purchaseId: 'purchase',
          supplierId: supplier,
          amount: 560,
          date: DateTime(2026, 9, 8),
          method: 'CASH');
      final paid = await pay();
      expect(await pay(), paid);
      expect(await balance(ap), -1440);
      await expectLater(
          FinancialVoidService.voidInvoice('purchase',
              purchase: true, reason: 'Cancel', database: db),
          throwsStateError);
      await VoucherPaymentService.reverseVoucher('supplier-pay',
          reason: 'Correct payment', database: db);
      expect(await balance(ap), -2000);
      expect(await balance(cash), 0);
      await FinancialVoidService.voidInvoice('purchase',
          purchase: true, reason: 'Cancel purchase', database: db);
      expect(await balance(ap), 0);
      expect(
          (await db.query('purchase_invoices',
                  where: 'id=?', whereArgs: ['purchase']))
              .single['amount_total'],
          2000);
      expect(
          await FinancialVoidService.voidInvoice('purchase',
              purchase: true, reason: 'Again', database: db),
          0);
      await expectLater(pay(), throwsStateError);
      final parties = await PartyFinancialService.balances(executor: db);
      expect(
          parties
              .singleWhere((p) => p.supplierLegacyId == '$supplier')
              .payableBalance,
          0);
      await expectLater(db.delete('app_audit_events'), throwsA(anything));
      await expectLater(db.delete('gl_entries'), throwsA(anything));
    } finally {
      await session.endEphemeralPreviewSession();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
