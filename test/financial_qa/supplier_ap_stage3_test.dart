import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/account_statements/suppliers/services/supplier_statement_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_payment_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/supplier_payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int supplierId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('supplier_ap_stage3_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'ap-stage3-owner');

    await PartyFinancialService.createParty(
      name: 'Stage3 Supplier',
      phone: '0599550000',
      address: 'Bethlehem',
      customer: false,
      supplier: true,
      database: db,
    );
    supplierId = (await db.query(
      'suppliers',
      columns: const ['id'],
      where: 'name=?',
      whereArgs: const ['Stage3 Supplier'],
      limit: 1,
    ))
        .single['id'] as int;
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<double> apBalance() async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS balance
      FROM gl_lines l
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code = ?
        AND UPPER(COALESCE(l.party_type,''))='SUPPLIER'
        AND CAST(l.party_id AS INTEGER)=?
    ''', ['2200.S${supplierId.toString().padLeft(4, '0')}', supplierId]);
    return (rows.single['balance'] as num).toDouble();
  }

  Future<double> paidFor(String invoiceId) async {
    final rows = await db.rawQuery(
      "SELECT ${PurchaseBalanceSql.paid('?')} AS paid",
      [invoiceId],
    );
    return (rows.single['paid'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> expectBalanced() async {
    final badEntries = await db.rawQuery('''
      SELECT entry_id
      FROM gl_lines
      GROUP BY entry_id
      HAVING ABS(SUM(debit-credit)) > 0.001
    ''');
    expect(badEntries, isEmpty);
    final total = await db.rawQuery(
      'SELECT COALESCE(SUM(debit-credit),0) AS d FROM gl_lines',
    );
    expect((total.single['d'] as num).toDouble(), closeTo(0, 0.001));
  }

  test(
      'AP3-010 supplier lifecycle reconciles invoice statement AP and reversal',
      () async {
    const invoiceId = 'AP3-INV-1';
    await PurchaseInvoiceService.createInvoice(
      id: invoiceId,
      supplierId: supplierId,
      date: DateTime(2026, 9, 20),
      note: 'Stage3 credit purchase',
      purchaseType: 'PARTS',
      method: 'credit',
      items: const [
        {'item_name': 'Parts A', 'qty': 2.0, 'price': 1000.0},
        {'item_name': 'Parts B', 'qty': 1.0, 'price': 1000.0},
      ],
    );

    final invoice = (await db.query(
      'purchase_invoices',
      where: 'id=?',
      whereArgs: const [invoiceId],
    ))
        .single;
    expect((invoice['amount_total'] as num).toDouble(), 3000);
    expect(invoice['status'], 'UNPAID');
    expect((invoice['remaining'] as num).toDouble(), 3000);

    final cashGl = await PurchasePaymentService.payPurchase(
      database: db,
      operationId: 'AP3-PAY-CASH',
      purchaseId: invoiceId,
      supplierId: supplierId,
      amount: 500,
      date: DateTime(2026, 9, 21),
      method: 'CASH',
    );
    final bankGl = await PurchasePaymentService.payPurchase(
      database: db,
      operationId: 'AP3-PAY-BANK',
      purchaseId: invoiceId,
      supplierId: supplierId,
      amount: 700,
      date: DateTime(2026, 9, 21),
      method: 'BANK',
    );

    expect(
      await PurchasePaymentService.payPurchase(
        database: db,
        operationId: 'AP3-PAY-CASH',
        purchaseId: invoiceId,
        supplierId: supplierId,
        amount: 500,
        date: DateTime(2026, 9, 21),
        method: 'CASH',
      ),
      cashGl,
    );
    await expectLater(
      PurchasePaymentService.payPurchase(
        database: db,
        operationId: 'AP3-PAY-CASH',
        purchaseId: invoiceId,
        supplierId: supplierId,
        amount: 500,
        date: DateTime(2026, 9, 21),
        method: 'BANK',
      ),
      throwsStateError,
    );

    await SupplierPaymentService.insertAndPost(
      database: db,
      operationId: 'AP3-ACCOUNT-PAY',
      supplierId: supplierId,
      amount: 100,
      date: DateTime(2026, 9, 21),
      method: 'CASH',
      note: 'Payment on supplier account',
    );

    expect(await paidFor(invoiceId), closeTo(1200, 0.001));
    expect(await apBalance(), closeTo(1700, 0.001));
    expect(
      await db.query(
        'invoice_settlements',
        where: 'invoice_id=?',
        whereArgs: const [invoiceId],
      ),
      hasLength(2),
      reason: 'Unreferenced account payment must not settle an invoice.',
    );

    await expectLater(
      PurchasePaymentService.payPurchase(
        database: db,
        operationId: 'AP3-OVERPAY',
        purchaseId: invoiceId,
        supplierId: supplierId,
        amount: 1900,
        date: DateTime(2026, 9, 21),
        method: 'CASH',
      ),
      throwsStateError,
    );
    expect(
      await db.query(
        'vouchers',
        where: 'id=?',
        whereArgs: const ['AP3-OVERPAY'],
      ),
      isEmpty,
    );
    await SupplierPaymentService.reverse(
      'AP3-PAY-BANK',
      database: db,
    );
    expect(await paidFor(invoiceId), closeTo(500, 0.001));
    expect(await apBalance(), closeTo(2400, 0.001));

    final statement = await SupplierStatementService.load(
      supplierId: '$supplierId',
      to: DateTime(2026, 9, 30),
      executor: db,
    );
    expect(statement.closingBalance, closeTo(2400, 0.001));
    expect(statement.lines, isNotEmpty);
    expect(
      statement.lines.every(
        (line) => line.entryId > 0 && line.source.isNotEmpty,
      ),
      isTrue,
    );

    final summaries = await PartyFinancialService.balances(executor: db);
    final summary = summaries.singleWhere(
      (row) => row.supplierLegacyId == '$supplierId',
    );
    expect(summary.totalPayable, closeTo(3000, 0.001));
    expect(summary.paid, closeTo(600, 0.001));
    expect(summary.payableBalance, closeTo(2400, 0.001));
    final history = await SupplierPaymentService.list(
      database: db,
      supplierId: '$supplierId',
    );
    expect(
      history.singleWhere((row) => row['id'] == 'AP3-PAY-BANK')['status'],
      'REVERSED',
    );
    expect(
      history.where((row) => row['id'] == 'AP3-PAY-CASH'),
      hasLength(1),
    );

    final purchaseEntry = await db.query(
      'gl_entries',
      where: 'source=? AND source_id=?',
      whereArgs: const ['PURCHASE', invoiceId],
    );
    expect(purchaseEntry, hasLength(1));
    expect(cashGl, isNot(bankGl));

    final supplierRoles = await db.query(
      'party_roles',
      where: 'role=? AND legacy_id=?',
      whereArgs: ['SUPPLIER', supplierId.toString()],
    );
    expect(supplierRoles, hasLength(1));
    await expectBalanced();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
