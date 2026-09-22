import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'V4-010 payment voucher numbering retry immutability and reversal stay atomic',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('voucher_stage4_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'voucher-stage4-owner');
    try {
      await PartyFinancialService.createParty(
        name: 'Voucher Supplier',
        phone: '0599000044',
        address: 'Bethlehem',
        customer: false,
        supplier: true,
        database: db,
      );
      final supplierId = (await db.query(
        'suppliers',
        columns: const ['id'],
        where: 'name=?',
        whereArgs: const ['Voucher Supplier'],
        limit: 1,
      ))
          .single['id'] as int;
      const invoiceId = 'V4-PURCHASE';
      await PurchaseInvoiceService.createInvoice(
        id: invoiceId,
        supplierId: supplierId,
        date: DateTime(2026, 9, 22),
        note: 'Voucher stage purchase',
        purchaseType: 'OTHER',
        method: 'credit',
        items: const [
          {'item_name': 'QA item', 'qty': 1.0, 'price': 1000.0}
        ],
      );

      Future<int> pay(String id, double amount) =>
          PurchasePaymentService.payPurchase(
            database: db,
            operationId: id,
            purchaseId: invoiceId,
            supplierId: supplierId,
            amount: amount,
            date: DateTime(2026, 9, 22),
            method: 'CASH',
          );

      final gl1 = await pay('V4-P1', 100);
      final gl2 = await pay('V4-P2', 100);
      final gl3 = await pay('V4-P3', 100);
      expect(await pay('V4-P2', 100), gl2);
      expect({gl1, gl2, gl3}.length, 3);
      final vouchers = await db.query(
        'vouchers',
        where: 'id IN (?,?,?)',
        whereArgs: const ['V4-P1', 'V4-P2', 'V4-P3'],
        orderBy: 'id',
      );
      expect(vouchers, hasLength(3));
      final numbers =
          vouchers.map((v) => v['voucher_number']?.toString() ?? '').toList();
      expect(numbers.every((n) => n.isNotEmpty), isTrue);
      expect(numbers.toSet(), hasLength(3));

      final seq = numbers.map((n) => int.parse(n.split('-').last)).toList()
        ..sort();
      expect(seq[1], seq[0] + 1);
      expect(seq[2], seq[1] + 1);

      await expectLater(
        db.update('vouchers', {'amount': 999.0},
            where: 'id=?', whereArgs: const ['V4-P2']),
        throwsA(anything),
      );
      final still = (await db
              .query('vouchers', where: 'id=?', whereArgs: const ['V4-P2']))
          .single;
      expect((still['amount'] as num).toDouble(), 100);

      await VoucherPaymentService.reverseVoucher(
        'V4-P2',
        reason: 'Stage4 formal reversal',
        database: db,
      );
      final reversed = (await db.query(
        'vouchers',
        where: 'id=?',
        whereArgs: const ['V4-P2'],
      ))
          .single;
      expect(reversed['status'], 'REVERSED');
      expect(reversed['reversal_gl_entry_id'], isNotNull);
      expect(reversed['reversal_reason'], 'Stage4 formal reversal');

      await expectLater(
        VoucherPaymentService.reverseVoucher(
          'V4-P2',
          reason: 'duplicate reversal',
          database: db,
        ),
        throwsStateError,
      );

      final paidRows = await db.rawQuery(
        "SELECT ${PurchaseBalanceSql.paid('?')} AS paid",
        const [invoiceId],
      );
      expect((paidRows.single['paid'] as num).toDouble(), 200);
      expect(
        await db.query('invoice_settlements',
            where: 'invoice_id=?', whereArgs: const [invoiceId]),
        hasLength(2),
      );

      final bad = await db.rawQuery('''
        SELECT entry_id FROM gl_lines GROUP BY entry_id
        HAVING ABS(SUM(debit-credit)) > 0.001
      ''');
      expect(bad, isEmpty);
      final audit = await db.query(
        'app_audit_events',
        where: 'action=? AND entity_id=?',
        whereArgs: const ['PAYMENT_VOUCHER_REVERSED', 'V4-P2'],
      );
      expect(audit, hasLength(1));
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
