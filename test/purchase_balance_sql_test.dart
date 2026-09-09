import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';

void main() {
  test(
      'ledger payment total handles mixed paths, reversals, cash and missing logs',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db
        .execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY, code TEXT)');
    await db.execute(
        'CREATE TABLE gl_entries(id INTEGER PRIMARY KEY, source TEXT, source_id TEXT, reversal_of INTEGER)');
    await db.execute(
        'CREATE TABLE gl_lines(entry_id INTEGER, account_id INTEGER, invoice_id TEXT, party_type TEXT, cheque_id INTEGER, debit REAL, credit REAL)');
    await db.insert('accounts', {'id': 1, 'code': '2200.S0001'});
    await db.insert('accounts', {'id': 2, 'code': '1000'});
    Future<void> payment(int id, String source, double amount,
        {String? invoice = 'i',
        int account = 1,
        String? party = 'SUPPLIER',
        int? reversal}) async {
      await db.insert('gl_entries', {
        'id': id,
        'source': source,
        'source_id': source == 'PURCHASE' ? 'i' : 'v$id',
        'reversal_of': reversal
      });
      await db.insert('gl_lines', {
        'entry_id': id,
        'account_id': account,
        'invoice_id': invoice,
        'party_type': party,
        'debit': account == 1 ? amount : 0,
        'credit': account == 2 ? amount : 0
      });
    }

    Future<double> paid({String? exclude}) async => ((await db.rawQuery(
                "SELECT ${PurchaseBalanceSql.paid('?', excludingVoucher: exclude == null ? null : '?')} AS paid",
                ['i', if (exclude != null) exclude]))
            .first['paid'] as num)
        .toDouble();
    expect(await paid(), 0);
    await payment(1, 'PURCHASE_PAYMENT', 560);
    await payment(2, 'VOUCHER', 100);
    expect(await paid(), 660);
    expect(await paid(exclude: 'v2'), 560);
    await payment(3, 'SUPPLIER_PAYMENT', 600, invoice: null);
    expect(await paid(), 660,
        reason: 'On-account payments are not invoice settlements');
    await payment(4, 'VOUCHER_REV', -100, reversal: 2);
    expect(await paid(), 560);
    await payment(5, 'PURCHASE', 200, invoice: null, account: 2, party: null);
    expect(await paid(), 760,
        reason: 'Immediate cash purchase is paid from its GL');
    await payment(6, 'VOUCHER', 300);
    await db.update('gl_lines', {'cheque_id': 9}, where: 'entry_id=6');
    expect(await paid(), 1060);
    await payment(7, 'CHEQUE_STATUS', -300, invoice: null);
    await db.update('gl_lines', {'cheque_id': 9}, where: 'entry_id=7');
    expect(await paid(), 760,
        reason: 'Historical cheque return resolves invoice from original GL');
  });
}
