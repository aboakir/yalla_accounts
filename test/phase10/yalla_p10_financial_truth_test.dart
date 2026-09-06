import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/core/services/db/views/accounting_views.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('P10 source-of-truth contracts', () {
    test('Repair model does not double-add legacy payment fields', () {
      final source = _read('lib/features/repairs/models/repair.dart');
      expect(source, contains('double get totalPaidAmount => paidAmount;'));
      expect(source, contains('double get customerCredit'));
      expect(source, contains('bool get isFinanciallySettled'));
      expect(
        source,
        contains(
          'bool get isClosed => isArchived && status == RepairStatusText.closed;',
        ),
      );
      expect(source, isNot(contains('bool get isClosed => isArchived;')));
    });

    test('PaymentService refresh never archives a financially settled repair',
        () {
      final source = _read(
        'lib/features/finance/payments/services/payment_service.dart',
      );
      expect(
        source,
        contains('RepairFinancialTruthService.refreshRepairPaymentCache'),
      );
      expect(source, isNot(contains("'isArchived': paidSum >= fileValue")));
    });

    test('Dashboard separates recognized revenue from collections', () {
      final source = _read('lib/features/home/screens/dashboard_screen.dart');
      expect(source, contains("a.code='4000'"));
      expect(source, contains("e.source='PAYMENT'"));
      expect(source, contains('monthlyIncomeTotal = monthlyIncomeFiles;'));
      expect(source, isNot(contains('SUM(fileValue + incomeAmount)')));
    });

    test('Repair reports do not use legacy paidAmount as financial truth', () {
      final ledger = _read(
        'lib/features/repairs/services/repair_ledger_query_service.dart',
      );
      final report = _read(
        'lib/features/repairs/services/repair_report_service.dart',
      );
      final stats = _read(
        'lib/features/repairs/services/repair_stats_service.dart',
      );
      expect(ledger, isNot(contains('fileValue - paidAmount')));
      expect(report, isNot(contains('fileValue - paidAmount')));
      expect(ledger, contains("a.code='4000'"));
      expect(ledger, contains('SUM(amount) AS paid'));
      expect(report, contains('SUM(amount) AS paid'));
      expect(stats, contains('FROM payments'));
    });

    test('Customer AR view is GL-based', () {
      final views = _read('lib/core/services/db/views/accounting_views.dart');
      final screen = _read(
        'lib/features/finance/screens/accounts_receivable_screen.dart',
      );
      expect(views, contains('WITH gl_ar AS'));
      expect(views, contains('(l.debit-l.credit) AS delta'));
      expect(views, contains("('CLIENT','CUSTOMER')"));
      expect(views, contains('COALESCE(gl_ar.balance_due,0) AS balance_due'));
      expect(screen, contains('DBService.getClientAR()'));
      expect(screen, contains("m['balance_due']"));
      expect(
        screen,
        contains('_filtered.fold(0.0, (s, r) => s + r.balance)'),
      );
    });

    test('Data Health includes P10 cache and AR reconciliation', () {
      final source = _read(
        'lib/features/settings/services/data_health_service.dart',
      );
      expect(source, contains("id: 'repair_payment_cache'"));
      expect(source, contains("id: 'repair_ar_reconciliation'"));
      expect(source, contains('_repairRepairPaymentCaches'));
      expect(source, contains("'total_paid_amount': paid"));
      expect(source, isNot(contains("'isArchived': paid")));
    });

    test('Finance income uses GL revenue 4000 before legacy fallbacks', () {
      final finance =
          _read('lib/features/finance/services/finance_service.dart');
      final report = _read(
        'lib/features/finance/services/finance_report_service.dart',
      );
      expect(finance, contains("a.code='4000'"));
      expect(finance, isNot(contains('SUM(incomeAmount)')));
      expect(report, contains("a.code='4000'"));
    });
  });

  test(
      'GL-backed client AR reflects adjustments instead of invoice-minus-payments',
      () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 1,
        onCreate: (db, version) async {
      await db.execute(
          'CREATE TABLE clients(id INTEGER PRIMARY KEY,name TEXT,account_id INTEGER)');
      await db.execute(
          'CREATE TABLE invoices(id TEXT,client_id INTEGER,total REAL)');
      await db.execute(
          'CREATE TABLE payments(id TEXT,client_id INTEGER,amount REAL,isIncome INTEGER)');
      await db
          .execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY,code TEXT)');
      await db.execute('''
        CREATE TABLE gl_lines(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id INTEGER,
          debit REAL,
          credit REAL,
          party_type TEXT,
          party_id TEXT
        )
      ''');
    });
    addTearDown(db.close);

    await db.insert('clients', {'id': 1, 'name': 'Client', 'account_id': 10});
    await db.insert('accounts', {'id': 10, 'code': '1200.C1'});
    await db.insert('invoices', {'id': 'I1', 'client_id': 1, 'total': 1000.0});
    await db.insert('payments', {
      'id': 'P1',
      'client_id': 1,
      'amount': 400.0,
      'isIncome': 1,
    });

    // AR charge includes a later +200 adjustment: 1200 debit, 400 credit.
    await db.insert('gl_lines', {
      'account_id': 10,
      'debit': 1200.0,
      'credit': 0.0,
      'party_type': 'CLIENT',
      'party_id': '1',
    });
    await db.insert('gl_lines', {
      'account_id': 10,
      'debit': 0.0,
      'credit': 400.0,
      'party_type': 'CLIENT',
      'party_id': '1',
    });

    final row = (await AccountingViews.getClientAR(db)).single;
    expect(row['invoices_total'], 1000.0);
    expect(row['payments_total'], 400.0);
    expect(row['balance_due'], 800.0,
        reason: 'Canonical AR must include the +200 GL adjustment');
  });

  test('RepairFinancialTruth reconciles file, payments, AR and credit',
      () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 1,
        onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE repairs(
          id TEXT PRIMARY KEY,
          fileValue REAL,
          paidAmount REAL,
          total_paid_amount REAL,
          paymentStatus TEXT,
          isArchived INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE payments(
          id TEXT PRIMARY KEY,
          repair_id TEXT,
          relatedRepairId TEXT,
          amount REAL,
          isIncome INTEGER DEFAULT 1
        )
      ''');
      await db.execute('''
        CREATE TABLE accounts(
          id INTEGER PRIMARY KEY,
          code TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE gl_lines(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id INTEGER,
          debit REAL,
          credit REAL,
          repair_id TEXT,
          party_type TEXT,
          party_id TEXT
        )
      ''');
    });

    addTearDown(db.close);

    await db.insert('repairs', {
      'id': 'R1',
      'fileValue': 1000.0,
      'paidAmount': 9999.0,
      'total_paid_amount': 9999.0,
      'paymentStatus': 'مسدد',
      'isArchived': 0,
    });
    await db.insert('accounts', {'id': 1, 'code': '1200.C1'});
    await db.insert('accounts', {'id': 2, 'code': '4000'});

    await db.insert('payments', {
      'id': 'P1',
      'repair_id': 'R1',
      'relatedRepairId': 'R1',
      'amount': 400.0,
      'isIncome': 1,
    });

    await db.insert('gl_lines', {
      'account_id': 1,
      'debit': 1000.0,
      'credit': 0.0,
      'repair_id': 'R1',
      'party_type': 'CLIENT',
      'party_id': '1',
    });
    await db.insert('gl_lines', {
      'account_id': 2,
      'debit': 0.0,
      'credit': 1000.0,
      'repair_id': 'R1',
    });
    await db.insert('gl_lines', {
      'account_id': 1,
      'debit': 0.0,
      'credit': 400.0,
      'repair_id': 'R1',
      'party_type': 'CLIENT',
      'party_id': '1',
    });

    var truth = await RepairFinancialTruthService.load('R1', executor: db);
    expect(truth.fileValue, 1000.0);
    expect(truth.paid, 400.0);
    expect(truth.remaining, 600.0);
    expect(truth.credit, 0.0);
    expect(truth.customerArBalance, 600.0);
    expect(truth.recognizedRevenue, 1000.0);

    await RepairFinancialTruthService.refreshRepairPaymentCache(db, 'R1');
    var row =
        (await db.query('repairs', where: 'id=?', whereArgs: ['R1'])).single;
    expect(row['paidAmount'], 400.0);
    expect(row['total_paid_amount'], 400.0);
    expect(row['paymentStatus'], 'مسدد جزئي');
    expect(row['isArchived'], 0);

    await db.insert('payments', {
      'id': 'P2',
      'repair_id': 'R1',
      'amount': 800.0,
      'isIncome': 1,
    });
    await db.insert('gl_lines', {
      'account_id': 1,
      'debit': 0.0,
      'credit': 800.0,
      'repair_id': 'R1',
      'party_type': 'CLIENT',
      'party_id': '1',
    });

    truth = await RepairFinancialTruthService.load('R1', executor: db);
    expect(truth.paid, 1200.0);
    expect(truth.remaining, 0.0);
    expect(truth.credit, 200.0);
    expect(truth.customerArBalance, -200.0);

    await RepairFinancialTruthService.refreshRepairPaymentCache(db, 'R1');
    row = (await db.query('repairs', where: 'id=?', whereArgs: ['R1'])).single;
    expect(row['paymentStatus'], 'مسدد');
    expect(row['isArchived'], 0,
        reason: 'Fully paid must not archive the repair');
  });
}
