import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/home/services/daily_dashboard_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_historical_reconciliation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final realDb = Platform.environment['YALLAH_TRACK_B_REAL_DB'];
  final realReport = Platform.environment['YALLAH_TRACK_B_INTEGRITY_REPORT'];

  Future<int> countSql(dynamic db, String sql, [List<Object?>? args]) async {
    final rows = await db.rawQuery(sql, args);
    return (rows.single.values.first as num).toInt();
  }

  test('B12 real-data integrity has no unexplained financial mismatch',
      () async {
    final path = realDb!;
    final report = realReport!;
    expect(File(path).existsSync(), isTrue);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      final repairIssues =
          await RepairHistoricalReconciliationService.audit(db);
      final repairableIssues = repairIssues.where((x) => x.repairable).toList();

      final balances = await PartyFinancialService.balances(executor: db);
      var customerStatementMismatch = 0;
      var supplierStatementMismatch = 0;
      var customerStatements = 0;
      var supplierStatements = 0;
      final supplierMismatchDetails = <Map<String, Object?>>[];

      for (final row in balances) {
        final customerId = row.customerLegacyId;
        if (customerId != null) {
          customerStatements++;
          final statement = await PartyFinancialService.statement(
            role: 'CUSTOMER',
            legacyId: int.parse(customerId),
            executor: db,
          );
          if ((statement.closingBalance - row.receivableBalance).abs() > 0.01) {
            customerStatementMismatch++;
          }
        }
        final supplierId = row.supplierLegacyId;
        if (supplierId != null) {
          supplierStatements++;
          final statement = await PartyFinancialService.statement(
            role: 'SUPPLIER',
            legacyId: int.parse(supplierId),
            executor: db,
          );
          if ((statement.closingBalance - row.payableBalance).abs() > 0.01) {
            supplierStatementMismatch++;
            supplierMismatchDetails.add({
              'supplier_id': supplierId,
              'party_id': row.partyId,
              'name': row.displayName,
              'balance_engine': row.payableBalance,
              'statement_closing': statement.closingBalance,
            });
          }
        }
      }

      final unbalancedGl = await countSql(db, '''
        SELECT COUNT(*) FROM (
          SELECT l.entry_id FROM gl_lines l
          GROUP BY l.entry_id
          HAVING ABS(SUM(l.debit-l.credit)) > 0.001
        )
      ''');
      final duplicateCanonicalPosting = await countSql(db, '''
        SELECT COUNT(*) FROM (
          SELECT source,source_id FROM gl_entries
          WHERE UPPER(source) IN (
            'PAYMENT','VOUCHER','INVOICE','PURCHASE','REPAIR_RECONCILIATION'
          )
            AND COALESCE(source_id,'')<>''
          GROUP BY source,source_id
          HAVING COUNT(*) > 1
        )
      ''');
      final orphanGlEntry = await countSql(db, '''
        SELECT COUNT(*) FROM gl_lines l
        LEFT JOIN gl_entries e ON e.id=l.entry_id
        WHERE e.id IS NULL
      ''');
      final orphanGlAccount = await countSql(db, '''
        SELECT COUNT(*) FROM gl_lines l
        LEFT JOIN accounts a ON a.id=l.account_id
        WHERE a.id IS NULL
      ''');
      final paymentWithoutGl = await countSql(db, '''
        SELECT COUNT(*) FROM payments p
        WHERE UPPER(COALESCE(p.status,'')) NOT IN ('VOID','REVERSED','CANCELLED')
          AND p.gl_entry_id IS NULL
      ''');
      final voucherWithoutGl = await countSql(db, '''
        SELECT COUNT(*) FROM vouchers v
        WHERE UPPER(COALESCE(v.status,'POSTED')) NOT IN
              ('VOID','REVERSED','CANCELLED')
          AND v.gl_entry_id IS NULL
      ''');
      final brokenPaymentGlRef = await countSql(db, '''
        SELECT COUNT(*) FROM payments p
        LEFT JOIN gl_entries e ON e.id=p.gl_entry_id
        WHERE p.gl_entry_id IS NOT NULL
          AND (
            e.id IS NULL OR
            (COALESCE(p.isIncome,0)=1 AND
              (UPPER(e.source)<>'PAYMENT' OR e.source_id<>p.id)) OR
            (COALESCE(p.isIncome,0)=0 AND (
              UPPER(e.source) NOT IN ('PAYMENT','PAYMENT_OUT','VOUCHER') OR
              (UPPER(e.source) IN ('PAYMENT','PAYMENT_OUT') AND e.source_id<>p.id) OR
              (UPPER(e.source)='VOUCHER' AND NOT EXISTS(
                SELECT 1 FROM vouchers v
                WHERE v.id=e.source_id AND v.gl_entry_id=e.id
              ))
            ))
          )
      ''');
      final brokenVoucherGlRef = await countSql(db, '''
        SELECT COUNT(*) FROM vouchers v
        LEFT JOIN gl_entries e ON e.id=v.gl_entry_id
        WHERE v.gl_entry_id IS NOT NULL
          AND (e.id IS NULL OR UPPER(e.source)<>'VOUCHER' OR e.source_id<>v.id)
      ''');
      final allocationWithoutPayment = await countSql(db, '''
        SELECT COUNT(*) FROM receipt_allocations a
        LEFT JOIN payments p ON p.id=a.payment_id
        WHERE p.id IS NULL
      ''');
      final allocationWithoutHeader = await countSql(db, '''
        SELECT COUNT(*) FROM receipt_allocations a
        LEFT JOIN receipt_headers h ON h.receipt_number=a.receipt_number
        WHERE h.receipt_number IS NULL
      ''');
      final paymentWithoutHeader = await countSql(db, '''
        SELECT COUNT(*) FROM payments p
        LEFT JOIN receipt_headers h ON h.receipt_number=p.receipt_number
        WHERE p.receipt_number IS NOT NULL
          AND h.receipt_number IS NULL
      ''');
      final receiptTotalMismatch = await countSql(db, '''
        SELECT COUNT(*) FROM receipt_headers h
        WHERE ABS(
          h.total_amount -
          (COALESCE(h.allocated_amount,0)+COALESCE(h.credit_amount,0))
        ) > 0.01
      ''');
      final activeInvoiceWithoutOriginalGl = await countSql(db, '''
        SELECT COUNT(*) FROM invoices i
        WHERE UPPER(COALESCE(i.status,'')) NOT IN
              ('VOID','CANCELLED','REVERSED')
          AND NOT EXISTS(
            SELECT 1 FROM gl_entries e
            WHERE UPPER(e.source)='INVOICE' AND e.source_id=i.id
          )
      ''');
      final unexplainedActiveInvoiceWithoutGl = await countSql(db, '''
        SELECT COUNT(*) FROM invoices i
        WHERE UPPER(COALESCE(i.status,'')) NOT IN
              ('VOID','CANCELLED','REVERSED')
          AND NOT EXISTS(
            SELECT 1 FROM gl_entries e
            WHERE UPPER(e.source)='INVOICE' AND e.source_id=i.id
          )
          AND NOT EXISTS(
            SELECT 1 FROM gl_entries e JOIN gl_lines l ON l.entry_id=e.id
            WHERE e.source='REPAIR_RECONCILIATION'
              AND e.source_id=i.repair_id AND l.invoice_id=i.id
          )
      ''');
      final activePurchaseWithoutGl = await countSql(db, '''
        SELECT COUNT(*) FROM purchase_invoices i
        WHERE UPPER(COALESCE(i.status,'')) NOT IN
              ('VOID','CANCELLED','REVERSED')
          AND NOT EXISTS(
            SELECT 1 FROM gl_entries e
            WHERE UPPER(e.source) IN ('PURCHASE','PURCHASE_INVOICE')
              AND e.source_id=i.id
          )
      ''');
      final unexplainedInvoiceMismatch = await countSql(db, '''
        SELECT COUNT(*) FROM invoices i
        JOIN repairs r ON r.id=i.repair_id
        WHERE UPPER(COALESCE(i.status,'')) NOT IN
              ('VOID','CANCELLED','REVERSED')
          AND ABS(COALESCE(i.total,0)-COALESCE(r.fileValue,0)) > 0.01
          AND NOT EXISTS(
            SELECT 1 FROM gl_entries e
            WHERE e.source='REPAIR_RECONCILIATION' AND e.source_id=r.id
          )
      ''');

      final negativeArWithoutCredit = await countSql(db, '''
        WITH paid AS (
          ${RepairFinancialTruthService.paidByRepairSql}
        ),
        ar AS (
          SELECT l.repair_id, SUM(l.debit-l.credit) balance
          FROM gl_lines l JOIN accounts a ON a.id=l.account_id
          WHERE l.repair_id IS NOT NULL
            AND (a.code='1200' OR a.code LIKE '1200.%')
          GROUP BY l.repair_id
        )
        SELECT COUNT(*) FROM repairs r
        LEFT JOIN paid p ON p.repair_id=r.id
        LEFT JOIN ar ON ar.repair_id=r.id
        WHERE COALESCE(ar.balance,0)<-0.01
          AND COALESCE(p.paid,0) <= COALESCE(r.fileValue,0)+0.01
      ''');
      final fullyPaidOpenAr = await countSql(db, '''
        WITH paid AS (
          ${RepairFinancialTruthService.paidByRepairSql}
        ),
        ar AS (
          SELECT l.repair_id, SUM(l.debit-l.credit) balance
          FROM gl_lines l JOIN accounts a ON a.id=l.account_id
          WHERE l.repair_id IS NOT NULL
            AND (a.code='1200' OR a.code LIKE '1200.%')
          GROUP BY l.repair_id
        )
        SELECT COUNT(*) FROM repairs r
        LEFT JOIN paid p ON p.repair_id=r.id
        LEFT JOIN ar ON ar.repair_id=r.id
        WHERE COALESCE(p.paid,0)+0.01>=COALESCE(r.fileValue,0)
          AND COALESCE(ar.balance,0)>0.01
      ''');

      final dashboard = await DailyDashboardService.loadOn(
        db,
        DashboardPeriod.month,
        DateTime(2026, 9, 20, 12),
        name: 'Track B Audit',
        currency: 'ILS',
      );
      var dashboardDetailMismatch = 0;
      for (final item in dashboard.collectionItems) {
        final truth = await RepairFinancialTruthService.load(
          item.repairId,
          executor: db,
        );
        if ((truth.outstandingBalance - item.amount).abs() > 0.01) {
          dashboardDetailMismatch++;
        }
      }

      final payload = <String, Object?>{
        'repair_issues_total': repairIssues.length,
        'repair_issues_repairable': repairableIssues.length,
        'repair_issues_explained':
            repairIssues.length - repairableIssues.length,
        'customer_statements_checked': customerStatements,
        'customer_statement_mismatch': customerStatementMismatch,
        'supplier_statements_checked': supplierStatements,
        'supplier_statement_mismatch': supplierStatementMismatch,
        'supplier_statement_mismatch_details': supplierMismatchDetails,
        'unbalanced_gl': unbalancedGl,
        'duplicate_canonical_posting': duplicateCanonicalPosting,
        'orphan_gl_entry': orphanGlEntry,
        'orphan_gl_account': orphanGlAccount,
        'payment_without_gl': paymentWithoutGl,
        'voucher_without_gl': voucherWithoutGl,
        'broken_payment_gl_reference': brokenPaymentGlRef,
        'broken_voucher_gl_reference': brokenVoucherGlRef,
        'allocation_without_payment': allocationWithoutPayment,
        'allocation_without_header': allocationWithoutHeader,
        'payment_receipt_without_header': paymentWithoutHeader,
        'receipt_total_mismatch': receiptTotalMismatch,
        'active_invoice_without_original_gl': activeInvoiceWithoutOriginalGl,
        'unexplained_active_invoice_without_gl':
            unexplainedActiveInvoiceWithoutGl,
        'active_purchase_without_gl': activePurchaseWithoutGl,
        'unexplained_invoice_total_mismatch': unexplainedInvoiceMismatch,
        'negative_ar_without_credit': negativeArWithoutCredit,
        'fully_paid_open_ar': fullyPaidOpenAr,
        'dashboard_items_checked': dashboard.collectionItems.length,
        'dashboard_detail_mismatch': dashboardDetailMismatch,
        'explained_repair_issues': repairIssues
            .where((x) => !x.repairable)
            .map((x) => x.toJson())
            .toList(),
      };
      await File(report).writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );

      expect(repairableIssues, isEmpty);
      expect(customerStatementMismatch, 0);
      expect(supplierStatementMismatch, 0);
      expect(unbalancedGl, 0);
      expect(duplicateCanonicalPosting, 0);
      expect(orphanGlEntry, 0);
      expect(orphanGlAccount, 0);
      expect(paymentWithoutGl, 0);
      expect(voucherWithoutGl, 0);
      expect(brokenPaymentGlRef, 0);
      expect(brokenVoucherGlRef, 0);
      expect(allocationWithoutPayment, 0);
      expect(allocationWithoutHeader, 0);
      expect(paymentWithoutHeader, 0);
      expect(receiptTotalMismatch, 0);
      expect(unexplainedActiveInvoiceWithoutGl, 0);
      expect(activePurchaseWithoutGl, 0);
      expect(unexplainedInvoiceMismatch, 0);
      expect(negativeArWithoutCredit, 0);
      expect(fullyPaidOpenAr, 0);
      expect(dashboardDetailMismatch, 0);
    } finally {
      await db.close();
      DatabaseMigration.useDatabaseForTesting(null);
    }
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: realDb == null || realReport == null
          ? 'Requires Track B real-data environment.'
          : false);
}
