import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

Future<Database> _db() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(
      'CREATE TABLE clients(id INTEGER PRIMARY KEY, name TEXT, type TEXT)');
  await db.execute('CREATE TABLE suppliers(id INTEGER PRIMARY KEY, name TEXT)');
  await db
      .execute('CREATE TABLE employees(id TEXT PRIMARY KEY, full_name TEXT)');
  await db.execute('''
    CREATE TABLE gl_entries(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      source TEXT,
      source_id TEXT,
      source_number TEXT,
      note TEXT,
      reversal_of INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE gl_lines(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id INTEGER NOT NULL,
      account_id INTEGER,
      debit REAL NOT NULL DEFAULT 0,
      credit REAL NOT NULL DEFAULT 0,
      party_type TEXT,
      party_id TEXT,
      invoice_id TEXT,
      repair_id TEXT,
      cheque_id TEXT
    )
  ''');
  return db;
}

Future<void> _line(
  Database db,
  int entryId, {
  required double debit,
  required double credit,
  String? partyType,
  String? partyId,
  String? invoiceId,
}) =>
    db.insert('gl_lines', {
      'entry_id': entryId,
      'debit': debit,
      'credit': credit,
      'party_type': partyType,
      'party_id': partyId,
      'invoice_id': invoiceId,
    });

void main() {
  test('Stage 3 Nawaura: purchase 1500 + payment 1500 = paid 1500 remain 0',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await db.insert('suppliers', {'id': 7, 'name': 'نواورة'});
    await PartyTables.ensure(db);

    final purchase = await db.insert('gl_entries', {
      'date': '2026-09-01T10:00:00',
      'source': 'PURCHASE',
      'source_id': 'PUR-1',
      'source_number': 'PUR-0001',
    });
    await _line(db, purchase,
        debit: 0,
        credit: 1500,
        partyType: 'SUPPLIER',
        partyId: '7',
        invoiceId: 'PUR-1');
    await _line(db, purchase, debit: 1500, credit: 0);

    final payment = await db.insert('gl_entries', {
      'date': '2026-09-02T10:00:00',
      'source': 'VOUCHER',
      'source_id': 'V-1',
      'source_number': 'PV-0001',
    });
    await _line(db, payment,
        debit: 1500,
        credit: 0,
        partyType: 'SUPPLIER',
        partyId: '7',
        invoiceId: 'PUR-1');
    await _line(db, payment, debit: 0, credit: 1500);

    final balances = await PartyFinancialService.balances(executor: db);
    final n = balances.singleWhere((p) => p.supplierLegacyId == '7');
    expect(n.totalPayable, 1500);
    expect(n.paid, 1500);
    expect(n.payableBalance, 0);
  });

  test(
      'Stage 3 one Party can own CUSTOMER and SUPPLIER roles without rewriting GL',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await db.insert(
        'clients', {'id': 3, 'name': 'جهة مزدوجة', 'type': 'individual'});
    await db.insert('suppliers', {'id': 9, 'name': 'جهة مزدوجة'});
    await PartyTables.ensure(db);

    await PartyFinancialService.linkCustomerAndSupplier(
      customerId: 3,
      supplierId: 9,
      executor: db,
    );

    final customerParty =
        await PartyTables.resolvePartyId(db, role: 'CUSTOMER', legacyId: 3);
    final supplierParty =
        await PartyTables.resolvePartyId(db, role: 'SUPPLIER', legacyId: 9);
    expect(customerParty, isNotNull);
    expect(supplierParty, customerParty);

    final rows = await db
        .query('party_roles', where: 'party_id=?', whereArgs: [customerParty]);
    expect(rows.map((r) => r['role']).toSet(),
        containsAll({'CUSTOMER', 'SUPPLIER'}));
  });

  test('Stage 3 statement respects period, running balance and reversal',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await db.insert(
        'clients', {'id': 4, 'name': 'عميل اختبار', 'type': 'individual'});
    await PartyTables.ensure(db);

    Future<int> entry(String date, String source, String no,
            {int? reversalOf}) =>
        db.insert('gl_entries', {
          'date': date,
          'source': source,
          'source_id': no,
          'source_number': no,
          'reversal_of': reversalOf,
        });

    final oldInvoice = await entry('2026-08-15T10:00:00', 'INVOICE', 'INV-OLD');
    await _line(db, oldInvoice,
        debit: 100, credit: 0, partyType: 'CUSTOMER', partyId: '4');
    final invoice = await entry('2026-09-02T10:00:00', 'INVOICE', 'INV-2');
    await _line(db, invoice,
        debit: 500, credit: 0, partyType: 'CUSTOMER', partyId: '4');
    final receipt = await entry('2026-09-03T10:00:00', 'PAYMENT', 'RC-2');
    await _line(db, receipt,
        debit: 0, credit: 200, partyType: 'CUSTOMER', partyId: '4');
    final reversal = await entry(
        '2026-09-04T10:00:00', 'PAYMENT_REVERSAL', 'RV-2',
        reversalOf: receipt);
    await _line(db, reversal,
        debit: 200, credit: 0, partyType: 'CUSTOMER', partyId: '4');

    final statement = await PartyFinancialService.statement(
      role: 'CUSTOMER',
      legacyId: 4,
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
      executor: db,
    );
    expect(statement.openingBalance, 100);
    expect(statement.lines.length, 3);
    expect(statement.lines[0].runningBalance, 600);
    expect(statement.lines[1].runningBalance, 400);
    expect(statement.lines[2].runningBalance, 600);
    expect(statement.closingBalance, 600);
  });
}
