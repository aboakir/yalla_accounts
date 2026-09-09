import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/features/finance/services/financial_overview_service.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE clients(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE suppliers(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE employees(
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE accounts(
      id INTEGER PRIMARY KEY,
      code TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      normal_balance TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE gl_entries(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      source TEXT NOT NULL,
      source_id TEXT NOT NULL,
      source_number TEXT,
      note TEXT,
      reversal_of INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE gl_lines(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id INTEGER NOT NULL,
      account_id INTEGER NOT NULL,
      debit REAL NOT NULL DEFAULT 0,
      credit REAL NOT NULL DEFAULT 0,
      party_type TEXT,
      party_id TEXT,
      invoice_id TEXT,
      repair_id TEXT,
      cheque_id TEXT,
      reference_id TEXT,
      reference_type TEXT
    )
  ''');

  final accounts = <Map<String, Object?>>[
    {
      'id': 1,
      'code': '1000',
      'name': 'الصندوق',
      'type': 'ASSET',
      'normal_balance': 'DEBIT'
    },
    {
      'id': 2,
      'code': '1010',
      'name': 'البنك',
      'type': 'ASSET',
      'normal_balance': 'DEBIT'
    },
    {
      'id': 3,
      'code': '1200',
      'name': 'ذمم العملاء',
      'type': 'ASSET',
      'normal_balance': 'DEBIT'
    },
    {
      'id': 4,
      'code': '2100',
      'name': 'ذمم الموردين',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT'
    },
    {
      'id': 5,
      'code': '2140.EE1',
      'name': 'مستحقات موظف',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT'
    },
    {
      'id': 6,
      'code': '3100',
      'name': 'أرصدة افتتاحية',
      'type': 'EQUITY',
      'normal_balance': 'CREDIT'
    },
    {
      'id': 7,
      'code': '4000',
      'name': 'الإيرادات',
      'type': 'REVENUE',
      'normal_balance': 'CREDIT'
    },
    {
      'id': 8,
      'code': '5005',
      'name': 'مشتريات',
      'type': 'EXPENSE',
      'normal_balance': 'DEBIT'
    },
    {
      'id': 9,
      'code': '5100',
      'name': 'مصروف رواتب',
      'type': 'EXPENSE',
      'normal_balance': 'DEBIT'
    },
  ];
  for (final row in accounts) {
    await db.insert('accounts', row);
  }

  await db.insert('clients', {'id': 1, 'name': 'عميل أ', 'type': 'individual'});
  await db.insert('suppliers', {'id': 2, 'name': 'مورد ب'});
  await db.insert('employees', {'id': 'E1', 'full_name': 'عامل ج'});
  await PartyTables.ensure(db);
  return db;
}

Future<int> _entry(
  Database db, {
  required String date,
  required String source,
  required String sourceId,
  String? sourceNumber,
  int? reversalOf,
}) async {
  return db.insert('gl_entries', {
    'date': date,
    'source': source,
    'source_id': sourceId,
    'source_number': sourceNumber,
    'note': sourceNumber,
    'reversal_of': reversalOf,
  });
}

Future<void> _line(
  Database db,
  int entryId, {
  required int accountId,
  required double debit,
  required double credit,
  String? partyType,
  String? partyId,
}) async {
  await db.insert('gl_lines', {
    'entry_id': entryId,
    'account_id': accountId,
    'debit': debit,
    'credit': credit,
    'party_type': partyType,
    'party_id': partyId,
  });
}

Future<void> _seed(Database db) async {
  var e = await _entry(
    db,
    date: '2026-08-31T10:00:00',
    source: 'OPENING',
    sourceId: 'OPEN-CASH',
  );
  await _line(db, e, accountId: 1, debit: 1000, credit: 0);
  await _line(db, e, accountId: 6, debit: 0, credit: 1000);

  e = await _entry(
    db,
    date: '2026-08-31T10:01:00',
    source: 'OPENING',
    sourceId: 'OPEN-BANK',
  );
  await _line(db, e, accountId: 2, debit: 500, credit: 0);
  await _line(db, e, accountId: 6, debit: 0, credit: 500);

  e = await _entry(
    db,
    date: '2026-09-01T09:00:00',
    source: 'INVOICE',
    sourceId: 'INV-1',
    sourceNumber: 'INV-0001',
  );
  await _line(db, e,
      accountId: 3,
      debit: 1000,
      credit: 0,
      partyType: 'CUSTOMER',
      partyId: '1');
  await _line(db, e, accountId: 7, debit: 0, credit: 1000);

  e = await _entry(
    db,
    date: '2026-09-02T09:00:00',
    source: 'PAYMENT',
    sourceId: 'RC-1',
    sourceNumber: 'RC-000001',
  );
  await _line(db, e, accountId: 1, debit: 400, credit: 0);
  await _line(db, e,
      accountId: 3, debit: 0, credit: 400, partyType: 'CUSTOMER', partyId: '1');

  e = await _entry(
    db,
    date: '2026-09-03T09:00:00',
    source: 'PURCHASE',
    sourceId: 'PUR-1',
    sourceNumber: 'PUR-0001',
  );
  await _line(db, e, accountId: 8, debit: 600, credit: 0);
  await _line(db, e,
      accountId: 4, debit: 0, credit: 600, partyType: 'SUPPLIER', partyId: '2');

  e = await _entry(
    db,
    date: '2026-09-04T09:00:00',
    source: 'VOUCHER',
    sourceId: 'PV-1',
    sourceNumber: 'PV-000001',
  );
  await _line(db, e,
      accountId: 4, debit: 250, credit: 0, partyType: 'SUPPLIER', partyId: '2');
  await _line(db, e, accountId: 2, debit: 0, credit: 250);

  e = await _entry(
    db,
    date: '2026-09-05T09:00:00',
    source: 'PAYROLL',
    sourceId: 'PAYROLL-1',
    sourceNumber: 'SAL-2026-09',
  );
  await _line(db, e,
      accountId: 9,
      debit: 300,
      credit: 0,
      partyType: 'EMPLOYEE',
      partyId: 'E1');
  await _line(db, e,
      accountId: 5,
      debit: 0,
      credit: 300,
      partyType: 'EMPLOYEE',
      partyId: 'E1');

  e = await _entry(
    db,
    date: '2026-09-06T09:00:00',
    source: 'VOUCHER',
    sourceId: 'PV-PAYROLL-1',
    sourceNumber: 'PV-000002',
  );
  await _line(db, e,
      accountId: 5,
      debit: 100,
      credit: 0,
      partyType: 'EMPLOYEE',
      partyId: 'E1');
  await _line(db, e, accountId: 1, debit: 0, credit: 100);
}

void main() {
  test(
      'customer and supplier statements retain opening and include whole end date',
      () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seed(db);
    final customer = await PartyFinancialService.statement(
        role: 'CUSTOMER',
        legacyId: 1,
        from: DateTime(2026, 9, 3),
        to: DateTime(2026, 9, 30),
        executor: db);
    final supplier = await PartyFinancialService.statement(
        role: 'SUPPLIER',
        legacyId: 2,
        from: DateTime(2026, 9, 4),
        to: DateTime(2026, 9, 30),
        executor: db);
    final overview = await FinancialOverviewService.loadOn(db,
        from: DateTime(2026, 9, 3), to: DateTime(2026, 9, 30));
    expect(customer.closingBalance, overview.customerReceivables);
    expect(supplier.closingBalance, overview.supplierPayables);
    final active = await PartyFinancialService.balances(
        from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30), executor: db);
    expect(active, isNotEmpty);
    final e = await _entry(db,
        date: '2026-09-30T23:59:59.999999',
        source: 'PAYMENT',
        sourceId: 'end-day');
    await _line(db, e, accountId: 1, debit: 25, credit: 0);
    await _line(db, e,
        accountId: 3,
        debit: 0,
        credit: 25,
        partyType: 'CUSTOMER',
        partyId: '1');
    final last = await PartyFinancialService.statement(
        role: 'CUSTOMER',
        legacyId: 1,
        from: DateTime(2026, 9, 30),
        to: DateTime(2026, 9, 30),
        executor: db);
    expect(last.openingBalance, 600);
    expect(last.closingBalance, 575);
  });
  test('cash account filters preserve transfer direction and reversals',
      () async {
    final db = await _openDb();
    addTearDown(db.close);
    final e = await _entry(db,
        date: '2026-09-01', source: 'TRANSFER', sourceId: 'cash-bank');
    await _line(db, e, accountId: 1, debit: 0, credit: 200);
    await _line(db, e, accountId: 2, debit: 200, credit: 0);
    final all = await FinancialOverviewService.cashFlowsOn(db,
        to: DateTime(2026, 9, 30));
    final cash = await FinancialOverviewService.cashFlowsOn(db,
        to: DateTime(2026, 9, 30), liquidityCode: '1000');
    final bank = await FinancialOverviewService.cashFlowsOn(db,
        to: DateTime(2026, 9, 30), liquidityCode: '1010');
    expect(all, (0.0, 0.0));
    expect(cash, (0.0, 200.0));
    expect(bank, (200.0, 0.0));
  });

  test(
      'period boundaries include legacy dates and fractional end of day, exclude outside lines',
      () async {
    final db = await _openDb();
    addTearDown(db.close);
    final dates = [
      '2026-08-31T23:59:59',
      '2026-09-01',
      '2026-09-01 12:30:00',
      '2026-09-30T23:59:59.999999',
      '2026-10-01'
    ];
    for (var i = 0; i < dates.length; i++) {
      final e = await _entry(db,
          date: dates[i], source: 'SALE', sourceId: 'boundary-$i');
      await _line(db, e, accountId: 1, debit: 100, credit: 0);
      await _line(db, e, accountId: 7, debit: 0, credit: 100);
    }
    final s = await FinancialOverviewService.loadOn(db,
        from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(s.revenue, 300);
    expect(s.receipts, 300);
    expect(s.cashBalance, 400);
    final totals = await FinancialOverviewService.accountTotalsOn(db,
        from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(totals.singleWhere((r) => r['code'] == '4000')['credit'], 300);
    final later = await FinancialOverviewService.loadOn(db,
        from: DateTime(2026, 9, 30), to: DateTime(2026, 9, 30));
    expect(later.revenue, 100);
    expect(later.cashBalance, 400);
  });

  test(
      'cash flows exclude opening and internal transfers and net formal reversals',
      () async {
    final db = await _openDb();
    addTearDown(db.close);
    Future<int> post(
        String source, String id, int debit, int credit, double amount,
        {int? reversal}) async {
      final e = await _entry(db,
          date: '2026-09-01',
          source: source,
          sourceId: id,
          reversalOf: reversal);
      await _line(db, e, accountId: debit, debit: amount, credit: 0);
      await _line(db, e, accountId: credit, debit: 0, credit: amount);
      return e;
    }

    await post('OPENING', 'opening', 1, 6, 1000);
    final receipt = await post('RECEIPT', 'r', 1, 3, 500);
    await post('TRANSFER', 'transfer', 2, 1, 200);
    await post('PAYMENT', 'p', 4, 2, 50);
    await post('REVERSAL', 'rv', 3, 1, 100, reversal: receipt);
    final flow = await FinancialOverviewService.cashFlowsOn(db,
        from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(flow.$1, 400);
    expect(flow.$2, 50);
  });

  test('Stage 5 overview reconciles balances and period activity from GL',
      () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seed(db);

    final s = await FinancialOverviewService.loadOn(
      db,
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
    );

    expect(s.cashBalance, 1300);
    expect(s.bankBalance, 250);
    expect(s.customerReceivables, 600);
    expect(s.customerCredits, 0);
    expect(s.supplierPayables, 350);
    expect(s.supplierAdvances, 0);
    expect(s.payrollPayables, 200);

    expect(s.revenue, 1000);
    expect(s.expenses, 900);
    expect(s.netProfit, 100);
    expect(s.collections, 400);
    expect(s.supplierPayments, 250);
    expect(s.payrollPayments, 100);

    expect(s.periodDebit, 2650);
    expect(s.periodCredit, 2650);
    expect(s.periodBalanced, isTrue);
    expect(s.integrityIssueCount, 0);
    expect(s.accountingHealthy, isTrue);
    expect(s.topAccounts, isNotEmpty);
    expect(s.recentEntries.length, 6);
  });

  test('Stage 5 balances are as-of while period activity respects from date',
      () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seed(db);

    final s = await FinancialOverviewService.loadOn(
      db,
      from: DateTime(2026, 9, 4),
      to: DateTime(2026, 9, 30),
    );

    // Opening and earlier September movements remain in as-of balances.
    expect(s.cashBalance, 1300);
    expect(s.bankBalance, 250);
    expect(s.customerReceivables, 600);
    expect(s.supplierPayables, 350);

    // Activity begins on 4 September.
    expect(s.revenue, 0);
    expect(s.expenses, 300);
    expect(s.collections, 0);
    expect(s.supplierPayments, 250);
    expect(s.payrollPayments, 100);
  });

  test('Stage 5 formal receipt reversal reduces collections and restores AR',
      () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _seed(db);

    final original = (await db.query(
      'gl_entries',
      columns: const ['id'],
      where: 'source_id=?',
      whereArgs: ['RC-1'],
      limit: 1,
    ))
        .single['id'] as int;

    final reversal = await _entry(
      db,
      date: '2026-09-07T09:00:00',
      source: 'REVERSAL',
      sourceId: 'RV-RC-1',
      sourceNumber: 'RV-000001',
      reversalOf: original,
    );
    await _line(db, reversal, accountId: 1, debit: 0, credit: 100);
    await _line(db, reversal,
        accountId: 3,
        debit: 100,
        credit: 0,
        partyType: 'CUSTOMER',
        partyId: '1');

    final s = await FinancialOverviewService.loadOn(
      db,
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
    );

    expect(s.collections, 300);
    expect(s.customerReceivables, 700);
    expect(s.cashBalance, 1200);
    expect(s.periodBalanced, isTrue);
  });
}
