import 'package:yalla_accounts/features/parties/services/party_report_service.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
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
  test(
      'period balances retain opening debt and reversals are not cash payments',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await db.insert('suppliers', {'id': 1, 'name': 'Period supplier'});
    await PartyTables.ensure(db);
    for (final row in [
      {'id': 1, 'date': '2026-08-01', 'source': 'PURCHASE'},
      {'id': 2, 'date': '2026-09-08', 'source': 'VOUCHER'},
      {'id': 3, 'date': '2026-09-09', 'source': 'PURCHASE'},
      {
        'id': 4,
        'date': '2026-09-10',
        'source': 'PURCHASE_REV',
        'reversal_of': 3
      },
    ]) {
      await db.insert('gl_entries', row);
    }
    await _line(db, 1,
        debit: 0, credit: 2000, partyType: 'SUPPLIER', partyId: '1');
    await _line(db, 2,
        debit: 560, credit: 0, partyType: 'SUPPLIER', partyId: '1');
    await _line(db, 3,
        debit: 0, credit: 100, partyType: 'SUPPLIER', partyId: '1');
    await _line(db, 4,
        debit: 100, credit: 0, partyType: 'SUPPLIER', partyId: '1');
    final rows = await PartyFinancialService.balances(
        executor: db, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    final supplier = rows.singleWhere((p) => p.isSupplier);
    expect(supplier.totalPayable, 2000);
    expect(supplier.paid, 560);
    expect(supplier.payableBalance, 1440);
  });

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
  test('combined party statement preserves both roles and period opening',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await db
        .insert('clients', {'id': 2, 'name': 'أبو طارق', 'type': 'individual'});
    await db.insert('suppliers', {'id': 2, 'name': 'أبو طارق'});
    await PartyTables.ensure(db);
    await PartyFinancialService.linkCustomerAndSupplier(
        customerId: 2, supplierId: 2, executor: db);
    final values = [
      ('CUSTOMER', 6200.0, 0.0, '2026-09-01T10:00:00'),
      ('CUSTOMER', 0.0, 430.0, '2026-09-02T10:00:00'),
      ('SUPPLIER', 0.0, 2000.0, '2026-09-03T10:00:00'),
      ('SUPPLIER', 560.0, 0.0, '2026-09-04T10:00:00'),
    ];
    for (final v in values) {
      final id =
          await db.insert('gl_entries', {'date': v.$4, 'source': 'TEST'});
      await _line(db, id,
          debit: v.$2, credit: v.$3, partyType: v.$1, partyId: '2');
    }
    final balances =
        (await PartyFinancialService.balances(executor: db)).single;
    expect(balances.receivableBalance, 5770);
    expect(balances.payableBalance, 1440);
    final all = await PartyFinancialService.statement(
        role: 'SUPPLIER', legacyId: 2, combined: true, executor: db);
    expect(all.closingBalance, 4330);
    expect(all.lines.map((l) => l.runningBalance), [6200, 5770, 3770, 4330]);
    final period = await PartyFinancialService.statement(
        role: 'CUSTOMER',
        legacyId: 2,
        combined: true,
        from: DateTime(2026, 9, 4),
        executor: db);
    expect(period.openingBalance, 3770);
    expect(period.lines.single.debit, 560);
    expect(period.closingBalance, 4330);
    expect((await db.query('gl_lines')).length, 4);
  });
  test('create dual role party atomically and reject duplicate identity',
      () async {
    final db = await _db();
    addTearDown(db.close);
    for (final col in ['phone', 'address', 'email', 'notes']) {
      await db.execute('ALTER TABLE clients ADD COLUMN $col TEXT');
    }
    for (final col in ['phone', 'address', 'pid']) {
      await db.execute('ALTER TABLE suppliers ADD COLUMN $col TEXT');
    }
    await PartyTables.ensure(db);
    await TechnicalTables.createAllTables(db);
    await PartyFinancialService.createParty(
        name: 'جهة جديدة',
        phone: '123',
        address: '',
        customer: true,
        supplier: true,
        database: db);
    final roles = await db.query('party_roles');
    expect(roles.length, 2);
    expect(roles.map((r) => r['party_id']).toSet().length, 1);
    expect((await db.query('clients')).length, 1);
    expect((await db.query('suppliers')).length, 1);
    await expectLater(
        PartyFinancialService.createParty(
            name: 'جهة جديدة',
            phone: '',
            address: '',
            customer: true,
            supplier: true,
            database: db),
        throwsStateError);
    await db.execute(
        "CREATE TRIGGER reject_supplier BEFORE INSERT ON suppliers BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(
        PartyFinancialService.createParty(
            name: 'فشل ذري',
            phone: '',
            address: '',
            customer: true,
            supplier: true,
            database: db),
        throwsA(isA<DatabaseException>()));
    expect((await db.query('clients')).length, 1);
    expect((await db.query('suppliers')).length, 1);
    expect((await db.query('outbox_messages')).length, 1);
  });
  test(
      'detailed report scopes documents to party and deduplicates paid invoices',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await db.insert('suppliers', {'id': 7, 'name': 'مورد'});
    await PartyTables.ensure(db);
    await db.execute(
        'CREATE TABLE purchase_invoices(id TEXT, supplier_id INTEGER, amount_total REAL, date TEXT)');
    await db.execute(
        'CREATE TABLE purchase_invoice_lines(invoice_id TEXT, item_name TEXT, qty REAL, unit_price REAL, total REAL)');
    await db.insert('purchase_invoices', {
      'id': 'P1',
      'supplier_id': 7,
      'amount_total': 2000,
      'date': '2026-09-01'
    });
    await db.insert('purchase_invoice_lines', {
      'invoice_id': 'P1',
      'item_name': 'مواد خام',
      'qty': 2,
      'unit_price': 1000,
      'total': 2000
    });
    for (final day in [1, 2]) {
      final id = await db.insert('gl_entries',
          {'date': '2026-09-0${day}T10:15:00', 'source': 'PURCHASE'});
      await _line(db, id,
          debit: day == 2 ? 560 : 0,
          credit: day == 1 ? 2000 : 0,
          partyType: 'SUPPLIER',
          partyId: '7',
          invoiceId: 'P1');
    }
    final report = await PartyReportService.load(
        role: 'SUPPLIER', legacyId: 7, database: db);
    expect(report.documents.length, 1);
    expect(report.documents.single.items.single['item_name'], 'مواد خام');
    expect(report.statement.closingBalance, -1440);
    final period = await PartyReportService.load(
        role: 'SUPPLIER',
        legacyId: 7,
        database: db,
        from: DateTime(2026, 9, 2));
    expect(period.statement.lines.length, 1);
    expect(period.statement.openingBalance, -2000);
    expect(period.documents.length, 1);
    expect(period.dates.values.single, '2026-09-02T10:15:00');
  });

  test('supplier statement accumulates precision before currency rounding',
      () async {
    final db = await _db();
    addTearDown(db.close);
    await db.insert('suppliers', {'id': 2, 'name': 'Fraction supplier'});
    await PartyTables.ensure(db);

    for (var i = 0; i < 4; i++) {
      final entry = await db.insert('gl_entries', {
        'date': '2026-09-0${i + 1}T10:00:00',
        'source': 'PURCHASE',
        'source_id': 'FRAC-$i',
      });
      await _line(db, entry,
          debit: 0, credit: 0.006, partyType: 'SUPPLIER', partyId: '2');
    }

    final balance = (await PartyFinancialService.balances(executor: db))
        .singleWhere((p) => p.supplierLegacyId == '2');
    final statement = await PartyFinancialService.statement(
      role: 'SUPPLIER',
      legacyId: 2,
      executor: db,
    );
    expect(balance.payableBalance, 0.02);
    expect(statement.closingBalance, balance.payableBalance);
    expect(statement.lines.last.runningBalance, 0.02);
  });
}
