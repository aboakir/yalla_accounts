import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_read_service.dart';
import 'package:yalla_accounts/features/finance/services/financial_overview_service.dart';
import 'package:yalla_accounts/features/finance/services/financial_void_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'P5-010 purchases and expenses classify post reverse and rollback atomically',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir =
        await Directory.systemTemp.createTemp('purchases_expenses_stage5_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'purchases-stage5-owner');
    try {
      await PartyFinancialService.createParty(
        name: 'Stage5 Supplier',
        phone: '0599000055',
        address: 'Bethlehem',
        customer: false,
        supplier: true,
        database: db,
      );
      final supplierId = (await db.query(
        'suppliers',
        columns: const ['id'],
        where: 'name=?',
        whereArgs: const ['Stage5 Supplier'],
        limit: 1,
      ))
          .single['id'] as int;

      const cases = <(String, String, String, double)>[
        ('P5-PARTS', 'PARTS', 'credit', 100.0),
        ('P5-RAW', 'RAW', 'cash', 200.0),
        ('P5-PAINT', 'PAINT', 'bank', 300.0),
        ('P5-TOOLS', 'TOOLS', 'credit', 400.0),
        ('P5-OTHER', 'OTHER', 'credit', 500.0),
      ];
      for (final c in cases) {
        await PurchaseInvoiceService.createInvoice(
          id: c.$1,
          supplierId: supplierId,
          date: DateTime(2026, 9, 22),
          note: 'Stage5 ${c.$2}',
          purchaseType: c.$2,
          method: c.$3,
          items: [
            {'item_name': c.$2, 'qty': 1.0, 'price': c.$4},
          ],
        );
      }

      const expectedDebitCode = {
        'P5-PARTS': '5005',
        'P5-RAW': '5310',
        'P5-PAINT': '5310',
        'P5-TOOLS': '5350',
        'P5-OTHER': '5900',
      };
      for (final entry in expectedDebitCode.entries) {
        final rows = await db.rawQuery('''
          SELECT a.code
          FROM gl_entries e
          JOIN gl_lines l ON l.entry_id=e.id
          JOIN accounts a ON a.id=l.account_id
          WHERE e.source='PURCHASE' AND e.source_id=? AND l.debit > 0.005
        ''', [entry.key]);
        expect(rows, hasLength(1));
        expect(rows.single['code'], entry.value, reason: entry.key);
      }

      final purchases = await PurchaseReadService.listAll();
      Map<String, Object?> purchase(String id) =>
          purchases.singleWhere((row) => row['id'] == id);
      expect(purchase('P5-RAW')['status'], 'PAID');
      expect((purchase('P5-RAW')['paid_total'] as num).toDouble(), 200);
      expect(purchase('P5-PAINT')['status'], 'PAID');
      expect((purchase('P5-PAINT')['paid_total'] as num).toDouble(), 300);
      expect(purchase('P5-PARTS')['status'], 'UNPAID');
      expect((purchase('P5-PARTS')['paid_total'] as num).toDouble(), 0);

      await VoucherPaymentService.insertAndPost(
        voucher: VoucherPayment(
          id: 'P5-EXPENSE',
          voucherType: 'PAYMENT',
          partyType: 'EXPENSE',
          partyId: 'OPERATING',
          amount: 75,
          currency: 'ILS',
          date: DateTime(2026, 9, 22),
          method: 'CASH',
          notes: 'Stage5 direct operating expense',
        ),
        partyName: 'مصاريف تشغيلية',
        database: db,
      );
      final totals = await FinancialOverviewService.accountTotalsOn(
        db,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30, 23, 59, 59),
      );
      Map<String, Object?> account(String code) =>
          totals.singleWhere((row) => row['code'] == code);
      expect((account('5005')['debit'] as num).toDouble(), 100);
      expect((account('5310')['debit'] as num).toDouble(), 500);
      expect((account('5350')['debit'] as num).toDouble(), 400);
      expect((account('5900')['debit'] as num).toDouble(), 500);
      expect((account('5000.OP')['debit'] as num).toDouble(), 75);

      await VoucherPaymentService.reverseVoucher(
        'P5-EXPENSE',
        reason: 'Reverse direct expense',
        database: db,
      );
      await FinancialVoidService.voidInvoice(
        'P5-TOOLS',
        purchase: true,
        reason: 'Cancel unused tools purchase',
        database: db,
      );

      Future<double> netFor(String code) async {
        final rows = await db.rawQuery('''
          SELECT COALESCE(SUM(l.debit-l.credit),0) AS n
          FROM gl_lines l JOIN accounts a ON a.id=l.account_id
          WHERE a.code=?
        ''', [code]);
        return (rows.single['n'] as num).toDouble();
      }

      expect(await netFor('5000.OP'), closeTo(0, 0.001));
      expect(await netFor('5350'), closeTo(0, 0.001));
      expect(
        (await db.query('purchase_invoices',
                where: 'id=?', whereArgs: const ['P5-TOOLS']))
            .single['status'],
        'VOID',
      );
      await db.execute('''
        CREATE TRIGGER reject_stage5_purchase_audit
        BEFORE INSERT ON app_audit_events
        WHEN NEW.action='PURCHASE_INVOICE_CREATED'
        BEGIN SELECT RAISE(ABORT,'stage5 audit unavailable'); END
      ''');
      await expectLater(
        PurchaseInvoiceService.createInvoice(
          id: 'P5-ROLLBACK',
          supplierId: supplierId,
          date: DateTime(2026, 9, 22),
          note: 'Must rollback',
          purchaseType: 'PARTS',
          method: 'credit',
          items: const [
            {'item_name': 'Rollback item', 'qty': 1.0, 'price': 123.0}
          ],
        ),
        throwsA(anything),
      );
      expect(
        await db.query('purchase_invoices',
            where: 'id=?', whereArgs: const ['P5-ROLLBACK']),
        isEmpty,
      );
      expect(
        await db.query('gl_entries',
            where: 'source=? AND source_id=?',
            whereArgs: const ['PURCHASE', 'P5-ROLLBACK']),
        isEmpty,
      );
      await db.execute('DROP TRIGGER reject_stage5_purchase_audit');

      await expectLater(
        PurchaseInvoiceService.createInvoice(
          id: 'P5-INVALID',
          supplierId: supplierId,
          date: DateTime(2026, 9, 22),
          note: 'Invalid',
          purchaseType: 'RAW',
          method: 'credit',
          items: const [
            {'item_name': 'Bad', 'qty': -1.0, 'price': 10.0}
          ],
        ),
        throwsArgumentError,
      );
      expect(
          await db.query('purchase_invoices',
              where: 'id=?', whereArgs: const ['P5-INVALID']),
          isEmpty);
      final badEntries = await db.rawQuery('''
        SELECT entry_id FROM gl_lines GROUP BY entry_id
        HAVING ABS(SUM(debit-credit)) > 0.001
      ''');
      expect(badEntries, isEmpty);
      final totalGl = await db.rawQuery(
        'SELECT COALESCE(SUM(debit-credit),0) AS n FROM gl_lines',
      );
      expect((totalGl.single['n'] as num).toDouble(), closeTo(0, 0.001));

      final createdAudit = await db.query(
        'app_audit_events',
        where: 'action=?',
        whereArgs: const ['PURCHASE_INVOICE_CREATED'],
      );
      expect(createdAudit, hasLength(5));
      final voidAudit = await db.query(
        'app_audit_events',
        where: 'action=? AND entity_id=?',
        whereArgs: const ['INVOICE_VOIDED', 'P5-TOOLS'],
      );
      expect(voidAudit, hasLength(1));
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
