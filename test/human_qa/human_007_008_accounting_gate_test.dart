import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String dbPath;
  late Database db;
  late dynamic session;
  late int clientId;
  late RepairFinancialTruth initial;
  late RepairFinancialTruth partial;
  late RepairFinancialTruth full;
  late RepairFinancialTruth reopened;
  late PartyBalanceSummary partialParty;
  late PartyBalanceSummary fullParty;
  late PartyLedgerStatement partialStatement;
  late int paymentsBeforeRetry;
  late int paymentsAfterRetry;
  late int glBeforeRetry;
  late int glAfterRetry;
  late int paymentRowsAfterFull;

  Future<int> count(
    String table, {
    String? where,
    List<Object?>? args,
  }) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $table'
      '${where == null ? '' : ' WHERE $where'}',
      args,
    );
    return (rows.single['n'] as num).toInt();
  }

  Future<PartyBalanceSummary> customerBalance() async {
    final rows = await PartyFinancialService.balances(executor: db);
    return rows.singleWhere(
      (row) => row.customerLegacyId == '$clientId',
    );
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('human_acc_gate_');
    dbPath = '${temp.path}/test.db';
    db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
    session = await startAccountingSession(db, 'human-qa');

    clientId = await db.insert('clients', {
      'name': 'Human QA Customer',
      'type': 'individual',
    });
    final revenue = (await db.query(
      'accounts',
      columns: ['id'],
      where: 'code=?',
      whereArgs: ['4000'],
    ))
        .single['id'] as int;
    final ar = await db.insert('accounts', {
      'code': '1200.C$clientId',
      'name': 'AR Human QA',
      'type': 'ASSET',
      'normal_balance': 'DEBIT',
    });
    await db.update(
      'clients',
      {'account_id': ar},
      where: 'id=?',
      whereArgs: [clientId],
    );
    await db.insert('repairs', {
      'id': 'R-HUMAN-ACC',
      'client_id': clientId,
      'fileValue': 17620.0,
      'paidAmount': 0.0,
      'total_paid_amount': 0.0,
      'paymentStatus': 'غير مسدد',
      'status': 'APPROVED',
      'receivedDate': '2026-09-19T00:00:00',
      'beneficiaryName': 'Human QA Customer',
    });
    await db.insert('invoices', {
      'id': 'I-HUMAN-ACC',
      'repair_id': 'R-HUMAN-ACC',
      'client_id': clientId,
      'date': '2026-09-19',
      'total': 17620.0,
      'status': 'UNPAID',
    });
    await db.update(
      'repairs',
      {'invoice_id': 'I-HUMAN-ACC'},
      where: 'id=?',
      whereArgs: ['R-HUMAN-ACC'],
    );
    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 9, 19),
      source: 'INVOICE',
      sourceId: 'I-HUMAN-ACC',
      lines: [
        {
          'account_id': ar,
          'debit': 17620.0,
          'credit': 0.0,
          'party_type': 'CLIENT',
          'party_id': clientId,
          'repair_id': 'R-HUMAN-ACC',
          'invoice_id': 'I-HUMAN-ACC',
        },
        {
          'account_id': revenue,
          'debit': 0.0,
          'credit': 17620.0,
          'repair_id': 'R-HUMAN-ACC',
          'invoice_id': 'I-HUMAN-ACC',
        },
      ],
    );

    initial = await RepairFinancialTruthService.load(
      'R-HUMAN-ACC',
      executor: db,
    );

    final first = await PaymentService.insertCanonicalReceipt(
      operationId: 'ACC-PARTIAL',
      database: db,
      clientId: clientId,
      customerName: 'Human QA Customer',
      method: 'cash',
      date: DateTime(2026, 9, 19),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'R-HUMAN-ACC',
          amount: 11810,
          paymentId: 'PAY-11810',
        ),
      ],
    );
    partial = await RepairFinancialTruthService.load(
      'R-HUMAN-ACC',
      executor: db,
    );
    partialParty = await customerBalance();
    partialStatement = await PartyFinancialService.statement(
      role: 'CUSTOMER',
      legacyId: clientId,
      executor: db,
    );
    paymentsBeforeRetry = await count(
      'payments',
      where: 'repair_id=?',
      args: ['R-HUMAN-ACC'],
    );
    glBeforeRetry = await count(
      'gl_entries',
      where: 'source=? AND source_id=?',
      args: ['PAYMENT', 'PAY-11810'],
    );

    final retry = await PaymentService.insertCanonicalReceipt(
      operationId: 'ACC-PARTIAL',
      database: db,
      clientId: clientId,
      customerName: 'Human QA Customer',
      method: 'cash',
      date: DateTime(2026, 9, 19),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'R-HUMAN-ACC',
          amount: 11810,
          paymentId: 'PAY-11810',
        ),
      ],
    );
    expect(retry.receiptNumber, first.receiptNumber);
    paymentsAfterRetry = await count(
      'payments',
      where: 'repair_id=?',
      args: ['R-HUMAN-ACC'],
    );
    glAfterRetry = await count(
      'gl_entries',
      where: 'source=? AND source_id=?',
      args: ['PAYMENT', 'PAY-11810'],
    );

    await PaymentService.insertCanonicalReceipt(
      operationId: 'ACC-FINAL',
      database: db,
      clientId: clientId,
      customerName: 'Human QA Customer',
      method: 'cash',
      date: DateTime(2026, 9, 19),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'R-HUMAN-ACC',
          amount: 5810,
          paymentId: 'PAY-5810',
        ),
      ],
    );
    full = await RepairFinancialTruthService.load(
      'R-HUMAN-ACC',
      executor: db,
    );
    fullParty = await customerBalance();
    paymentRowsAfterFull = await count(
      'payments',
      where: 'repair_id=?',
      args: ['R-HUMAN-ACC'],
    );

    await PaymentService.insertCanonicalReceipt(
      operationId: 'ACC-OVERFLOW',
      database: db,
      clientId: clientId,
      customerName: 'Human QA Customer',
      method: 'cash',
      date: DateTime(2026, 9, 19),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'R-HUMAN-ACC',
          amount: 100,
          paymentId: 'PAY-OVERFLOW',
        ),
      ],
    );
    full = await RepairFinancialTruthService.load(
      'R-HUMAN-ACC',
      executor: db,
    );

    await session.endEphemeralPreviewSession();
    await db.close();
    db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    reopened = await RepairFinancialTruthService.load(
      'R-HUMAN-ACC',
      executor: db,
    );
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('TEST-ACC-001 client exists in real isolated database', () async {
    final rows = await db.query(
      'clients',
      where: 'id=?',
      whereArgs: [clientId],
    );
    expect(rows, hasLength(1));
  });

  test('TEST-ACC-002 repair gross total is 17,620', () {
    expect(initial.repairGrossTotal, 17620.0);
    expect(initial.ledgerGrossTotal, 17620.0);
    expect(initial.isLedgerConsistent, isTrue);
  });

  test('TEST-ACC-003 no payments means outstanding 17,620', () {
    expect(initial.paymentsAllocated, 0.0);
    expect(initial.outstandingBalance, 17620.0);
    expect(initial.ledgerOutstanding, 17620.0);
  });

  test('TEST-ACC-004 partial 11,810 propagates to all financial truth', () {
    expect(partial.repairGrossTotal, 17620.0);
    expect(partial.paymentsAllocated, 11810.0);
    expect(partial.outstandingBalance, 5810.0);
    expect(partial.ledgerOutstanding, 5810.0);
    expect(partialParty.received, 11810.0);
    expect(partialParty.receivableBalance, 5810.0);
    expect(partialStatement.closingBalance, 5810.0);
  });

  test('TEST-ACC-005 final 5,810 closes obligation everywhere', () {
    expect(full.repairGrossTotal, 17620.0);
    expect(full.paymentsAllocated, 17620.0);
    expect(full.outstandingBalance, 0.0);
    expect(full.ledgerOutstanding, 0.0);
    expect(fullParty.receivableBalance, 0.0);
    expect(full.isFinanciallySettled, isTrue);
  });

  test('TEST-ACC-006 no duplicate payment rows', () {
    expect(paymentsBeforeRetry, 1);
    expect(paymentsAfterRetry, 1);
    expect(paymentRowsAfterFull, 2);
  });

  test('TEST-ACC-007 no duplicate accounting posting on retry', () {
    expect(glBeforeRetry, 1);
    expect(glAfterRetry, 1);
  });

  test('TEST-ACC-008 restart preserves exact values', () {
    expect(reopened.repairGrossTotal, 17620.0);
    expect(reopened.paymentsAllocated, 17620.0);
    expect(reopened.outstandingBalance, 0.0);
    expect(reopened.ledgerOutstanding, 0.0);
  });

  test('TEST-ACC-009 reload is deterministic', () async {
    final again = await RepairFinancialTruthService.load(
      'R-HUMAN-ACC',
      executor: db,
    );
    expect(again.repairGrossTotal, reopened.repairGrossTotal);
    expect(again.paymentsAllocated, reopened.paymentsAllocated);
    expect(again.outstandingBalance, reopened.outstandingBalance);
  });

  test('TEST-ACC-010 receipt retry is idempotent', () {
    expect(paymentsBeforeRetry, paymentsAfterRetry);
    expect(glBeforeRetry, glAfterRetry);
  });

  test('TEST-ACC-011 customer receivables equal open obligations', () {
    expect(partialParty.receivableBalance, partial.outstandingBalance);
  });

  test('TEST-ACC-012 repair total is one canonical number across views', () {
    expect(partial.repairGrossTotal, 17620.0);
    expect(partialParty.totalReceivable, 17620.0);
    final invoiceDebit = partialStatement.lines
        .where((line) => line.source.toUpperCase() == 'INVOICE')
        .fold<double>(0, (sum, line) => sum + line.debit);
    expect(invoiceDebit, 17620.0);
  });

  test('TEST-ACC-013 partial payment never reports 100 percent', () {
    expect(partial.isFinanciallySettled, isFalse);
    expect(partial.outstandingBalance, greaterThan(0));
  });

  test('TEST-ACC-014 full payment reports fully paid', () {
    expect(full.isFinanciallySettled, isTrue);
    expect(full.outstandingBalance, 0.0);
  });

  test('TEST-ACC-015 over-allocation cannot make outstanding negative', () {
    expect(full.outstandingBalance, 0.0);
    expect(full.paymentsAllocated, 17620.0);
    expect(full.credit, 0.0);
  });

  test('AR repair details use RepairFinancialTruthService only', () {
    final source = File(
      'lib/features/finance/screens/accounts_receivable_screen.dart',
    ).readAsStringSync();
    expect(source, contains('RepairFinancialTruthService.load('));
    expect(source, contains('invoiceTotal: truth.fileValue'));
    expect(source, contains('paid: truth.paid'));
    expect(source, isNot(contains('final invByRid')));
    expect(source, isNot(contains('final paidByRid')));
  });

  test('posted repair value cannot bypass audited edit path', () {
    final source = File(
      'lib/features/repairs/services/repair_database_service.dart',
    ).readAsStringSync();
    expect(source, contains('financiallyPosted'));
    expect(
      source,
      contains('Financial repair value changes must use the audited'),
    );
  });
}
