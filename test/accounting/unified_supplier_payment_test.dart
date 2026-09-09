import '../support/accounting_session.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_payment_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/supplier_payment_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'mixed payment paths enforce outstanding, replay identity and atomic rollback',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final temp =
        await Directory.systemTemp.createTemp('supplier_posting_test_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    final session = await startAccountingSession(db, 'test-accountant');

    addTearDown(() async {
      await session.endEphemeralPreviewSession();
      await db.close();
      await temp.delete(recursive: true);
    });
    final supplier = await db.insert('suppliers', {'name': 'Test supplier'});
    await db.insert('purchase_invoices', {
      'id': 'invoice',
      'supplier_id': supplier,
      'amount_total': 2000.0,
      'paid_total': 0.0,
      'date': '2026-09-08',
      'method': 'credit'
    });
    final cash =
        (await db.query('accounts', where: 'code=?', whereArgs: ['1000']))
            .first['id'];
    final ap = await db.insert('accounts', {
      'code': '2200.S${supplier.toString().padLeft(4, '0')}',
      'name': 'Test supplier',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT'
    });
    await AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 8),
        source: 'PURCHASE_PAYMENT',
        sourceId: 'legacy-payment',
        lines: [
          {
            'account_id': ap,
            'debit': 560.0,
            'credit': 0.0,
            'party_type': 'SUPPLIER',
            'party_id': supplier,
            'invoice_id': 'invoice'
          },
          {'account_id': cash, 'debit': 0.0, 'credit': 560.0}
        ]);
    Future<int> pay(String id, double amount, {String method = 'CASH'}) =>
        PurchasePaymentService.payPurchase(
            database: db,
            operationId: id,
            purchaseId: 'invoice',
            supplierId: supplier,
            amount: amount,
            date: DateTime(2026, 9, 8),
            method: method);
    await expectLater(pay('too-much', 2000), throwsStateError);
    expect(await db.query('vouchers', where: 'id=?', whereArgs: ['too-much']),
        isEmpty);
    final gl = await pay('balance', 1440);
    expect(await pay('balance', 1440), gl);
    final postedLines =
        await db.query('gl_lines', where: 'entry_id=?', whereArgs: [gl]);
    expect(
        postedLines.singleWhere((l) => l['account_id'] == ap)['debit'], 1440);
    expect(postedLines.singleWhere((l) => l['account_id'] == cash)['credit'],
        1440);
    await expectLater(pay('balance', 1440, method: 'BANK'), throwsStateError);
    final total = (await db
            .rawQuery("SELECT ${PurchaseBalanceSql.paid("'invoice'")} AS paid"))
        .first['paid'];
    expect(total, 2000);
    expect(
        (await db.query('invoice_settlements',
                where: 'invoice_id=?', whereArgs: ['invoice']))
            .length,
        1);
    Future<int> accountPayment(String id) =>
        SupplierPaymentService.insertAndPost(
            database: db,
            operationId: id,
            supplierId: supplier,
            amount: 10,
            date: DateTime(2026, 9, 8),
            method: 'CASH');
    final first = await accountPayment('a');
    expect(await accountPayment('a'), first);
    expect(await accountPayment('b'), isNot(first));
    final history = await SupplierPaymentService.list(
        database: db, supplierId: '$supplier');
    expect(history.length, 4,
        reason: 'Legacy payment and three vouchers appear once each');
    await SupplierPaymentService.reverse('balance', database: db);
    expect(
        (await db.rawQuery(
                "SELECT ${PurchaseBalanceSql.paid("'invoice'")} AS paid"))
            .first['paid'],
        560);
    expect(
        await db.query('invoice_settlements',
            where: 'invoice_id=?', whereArgs: ['invoice']),
        isEmpty);
    final reversed = await SupplierPaymentService.list(
        database: db, supplierId: '$supplier');
    expect(reversed.singleWhere((r) => r['id'] == 'balance')['status'],
        'REVERSED');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
