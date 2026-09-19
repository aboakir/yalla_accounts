import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int clientId;
  late int arId;
  late int revenueId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cheque_received_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'cheque-owner');
    clientId = await db.insert('clients', {
      'name': 'Cheque Customer',
      'type': 'individual',
    });
    arId = await db.insert('accounts', {
      'code': '1200.C$clientId',
      'name': 'Cheque Customer AR',
      'type': 'ASSET',
      'normal_balance': 'DEBIT',
    });
    await db.update(
      'clients',
      {'account_id': arId},
      where: 'id=?',
      whereArgs: [clientId],
    );
    revenueId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['4000'],
      limit: 1,
    ))
        .single['id'] as int;
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> createRepair(String id, double amount) async {
    await db.insert('repairs', {
      'id': id,
      'client_id': clientId,
      'fileValue': amount,
      'paidAmount': 0.0,
      'total_paid_amount': 0.0,
      'paymentStatus': 'غير مسدد',
      'status': 'APPROVED',
      'receivedDate': '2026-09-19T00:00:00',
    });
    await db.insert('invoices', {
      'id': 'INV-$id',
      'repair_id': id,
      'client_id': clientId,
      'date': '2026-09-19',
      'total': amount,
      'paid': 0.0,
      'status': 'UNPAID',
    });
    await db.update(
      'repairs',
      {'invoice_id': 'INV-$id'},
      where: 'id=?',
      whereArgs: [id],
    );
    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 9, 19),
      source: 'INVOICE',
      sourceId: 'INV-$id',
      lines: [
        {
          'account_id': arId,
          'debit': amount,
          'credit': 0.0,
          'party_type': 'CLIENT',
          'party_id': clientId,
          'repair_id': id,
          'invoice_id': 'INV-$id',
        },
        {
          'account_id': revenueId,
          'debit': 0.0,
          'credit': amount,
          'repair_id': id,
          'invoice_id': 'INV-$id',
        },
      ],
    );
  }

  Map<String, dynamic> chequeDraft(String key, double amount) => {
        'uuid': 'uuid-$key',
        'instrument_key': key,
        'cheque_no': 'NO-$key',
        'drawer_name': 'Cheque Customer',
        'bank_name': 'Palestine Bank',
        'bank_branch': 'Bethlehem',
        'issue_date': '2026-09-19T00:00:00',
        'due_date': '2026-10-19T00:00:00',
        'amount': amount,
      };

  Future<double> outstanding(String repairId) async {
    final truth =
        await RepairFinancialTruthService.load(repairId, executor: db);
    return truth.outstandingBalance;
  }

  test('RCV-001 cash receipt does not create cheque', () async {
    await createRepair('R-CASH', 1000);
    final result = await PaymentService.insertCanonicalReceiptWithInstruments(
      operationId: 'RCV-CASH',
      database: db,
      clientId: clientId,
      customerName: 'Cheque Customer',
      date: DateTime(2026, 9, 19),
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'cash-1',
          method: 'cash',
          amount: 500,
          allocations: [
            ReceiptAllocationInput(repairId: 'R-CASH', amount: 500),
          ],
        ),
      ],
    );
    expect(result.allocatedAmount, 500);
    expect(await db.query('cheques'), isEmpty);
    expect(await outstanding('R-CASH'), 500);
  });

  test('RCV-002..008 one cheque allocates across multiple repairs exactly once',
      () async {
    await createRepair('R-A', 5000);
    await createRepair('R-B', 3000);
    await createRepair('R-C', 2000);

    final result = await PaymentService.insertCanonicalReceiptWithInstruments(
      operationId: 'RCV-MULTI',
      database: db,
      clientId: clientId,
      customerName: 'Cheque Customer',
      date: DateTime(2026, 9, 19),
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: 'chq-7000',
          method: 'cheque',
          amount: 7000,
          chequeDraft: chequeDraft('chq-7000', 7000),
          allocations: const [
            ReceiptAllocationInput(repairId: 'R-A', amount: 5000),
            ReceiptAllocationInput(repairId: 'R-B', amount: 2000),
          ],
        ),
      ],
    );

    expect(result.allocatedAmount, 7000);
    expect(result.customerCredit, 0);
    expect(await outstanding('R-A'), 0);
    expect(await outstanding('R-B'), 1000);
    expect(await outstanding('R-C'), 2000);

    final cheques = await db.query('cheques');
    expect(cheques, hasLength(1));
    expect(cheques.single['amount'], 7000.0);
    expect(cheques.single['direction'], 'RECEIVED');
    expect(cheques.single['status'], 'received');
    expect(cheques.single['client_id'], clientId);
    expect(cheques.single['receipt_voucher_id'], result.receiptNumber);

    final chequeId = cheques.single['id'] as int;
    final links = await db.query(
      'cheque_voucher_links',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
    );
    expect(links, hasLength(1));
    expect(links.single['voucher_type'], 'RECEIPT');
    expect(links.single['voucher_id'], result.receiptNumber.toString());

    final allocations = await db.query(
      'cheque_allocations',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
      orderBy: 'target_id',
    );
    expect(allocations, hasLength(2));
    expect(
      allocations.fold<double>(
        0,
        (sum, row) => sum + (row['amount'] as num).toDouble(),
      ),
      7000,
    );
    final payments = await db.query(
      'payments',
      where: 'receipt_number=?',
      whereArgs: [result.receiptNumber],
    );
    expect(payments, hasLength(2));
    expect(payments.map((p) => p['cheque_id']).toSet(), {chequeId});

    final retry = await PaymentService.insertCanonicalReceiptWithInstruments(
      operationId: 'RCV-MULTI',
      database: db,
      clientId: clientId,
      customerName: 'Cheque Customer',
      date: DateTime(2026, 9, 19),
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: 'chq-7000',
          method: 'cheque',
          amount: 7000,
          chequeDraft: chequeDraft('chq-7000', 7000),
          allocations: const [
            ReceiptAllocationInput(repairId: 'R-A', amount: 5000),
            ReceiptAllocationInput(repairId: 'R-B', amount: 2000),
          ],
        ),
      ],
    );
    expect(retry.receiptNumber, result.receiptNumber);
    expect(await db.query('cheques'), hasLength(1));
    expect(
      await db.query(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['PAYMENT'],
      ),
      hasLength(2),
    );
  });

  test('RCV-009 multiple cheques can settle one repair', () async {
    await createRepair('R-MANY', 5000);

    Future<void> receive(String op, String key, double amount) async {
      await PaymentService.insertCanonicalReceiptWithInstruments(
        operationId: op,
        database: db,
        clientId: clientId,
        customerName: 'Cheque Customer',
        date: DateTime(2026, 9, 19),
        instruments: [
          ReceiptInstrumentInput(
            instrumentKey: key,
            method: 'cheque',
            amount: amount,
            chequeDraft: chequeDraft(key, amount),
            allocations: [
              ReceiptAllocationInput(repairId: 'R-MANY', amount: amount),
            ],
          ),
        ],
      );
    }

    await receive('RCV-MANY-1', 'many-1', 3000);
    expect(await outstanding('R-MANY'), 2000);
    await receive('RCV-MANY-2', 'many-2', 2000);
    expect(await outstanding('R-MANY'), 0);
    expect(await db.query('cheques'), hasLength(2));
  });

  test('RCV-010 cheque plus cash coexist in one receipt', () async {
    await createRepair('R-MIX', 5000);

    final result = await PaymentService.insertCanonicalReceiptWithInstruments(
      operationId: 'RCV-MIXED',
      database: db,
      clientId: clientId,
      customerName: 'Cheque Customer',
      date: DateTime(2026, 9, 19),
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: 'mix-cheque',
          method: 'cheque',
          amount: 3000,
          chequeDraft: chequeDraft('mix-cheque', 3000),
          allocations: const [
            ReceiptAllocationInput(repairId: 'R-MIX', amount: 3000),
          ],
        ),
        const ReceiptInstrumentInput(
          instrumentKey: 'mix-cash',
          method: 'cash',
          amount: 2000,
          allocations: [
            ReceiptAllocationInput(repairId: 'R-MIX', amount: 2000),
          ],
        ),
      ],
    );

    expect(result.allocatedAmount, 5000);
    expect(await outstanding('R-MIX'), 0);

    final header = (await db.query(
      'receipt_headers',
      where: 'receipt_number=?',
      whereArgs: [result.receiptNumber],
    ))
        .single;
    expect(header['method'], 'mixed');
    expect(header['total_amount'], 5000.0);

    final instruments = await db.query(
      'receipt_instruments',
      where: 'receipt_number=?',
      whereArgs: [result.receiptNumber],
    );
    expect(instruments, hasLength(2));
    expect(instruments.where((x) => x['cheque_id'] != null), hasLength(1));
    expect(await db.query('cheques'), hasLength(1));
  });

  test('RCV larger cheque converts true excess to customer credit', () async {
    await createRepair('R-CREDIT', 5000);

    final result = await PaymentService.insertCanonicalReceiptWithInstruments(
      operationId: 'RCV-CREDIT',
      database: db,
      clientId: clientId,
      customerName: 'Cheque Customer',
      date: DateTime(2026, 9, 19),
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: 'credit-cheque',
          method: 'cheque',
          amount: 7000,
          chequeDraft: chequeDraft('credit-cheque', 7000),
          allocations: const [
            ReceiptAllocationInput(repairId: 'R-CREDIT', amount: 7000),
          ],
        ),
      ],
    );

    expect(result.allocatedAmount, 5000);
    expect(result.customerCredit, 2000);
    expect(await outstanding('R-CREDIT'), 0);

    final cheque = (await db.query('cheques')).single;
    final chequeId = cheque['id'] as int;
    final chequeAllocations = await db.query(
      'cheque_allocations',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
    );
    expect(chequeAllocations, hasLength(2));
    expect(
      chequeAllocations.fold<double>(
        0,
        (sum, row) => sum + (row['amount'] as num).toDouble(),
      ),
      7000,
    );
  });

  test('received cheque transaction rolls back all rows on late failure',
      () async {
    await createRepair('R-ROLLBACK', 1000);

    await db.execute('''
      CREATE TRIGGER reject_receipt_header
      BEFORE INSERT ON receipt_headers
      BEGIN SELECT RAISE(ABORT,'late receipt failure'); END
    ''');

    await expectLater(
      PaymentService.insertCanonicalReceiptWithInstruments(
        operationId: 'RCV-ROLLBACK',
        database: db,
        clientId: clientId,
        customerName: 'Cheque Customer',
        date: DateTime(2026, 9, 19),
        instruments: [
          ReceiptInstrumentInput(
            instrumentKey: 'rollback-cheque',
            method: 'cheque',
            amount: 1000,
            chequeDraft: chequeDraft('rollback-cheque', 1000),
            allocations: const [
              ReceiptAllocationInput(repairId: 'R-ROLLBACK', amount: 1000),
            ],
          ),
        ],
      ),
      throwsA(anything),
    );

    expect(await db.query('cheques'), isEmpty);
    expect(await db.query('payments'), isEmpty);
    expect(await db.query('receipt_instruments'), isEmpty);
    expect(await db.query('cheque_allocations'), isEmpty);
    expect(
      await db.query(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['PAYMENT'],
      ),
      isEmpty,
    );
    expect(await outstanding('R-ROLLBACK'), 1000);
  });
}
