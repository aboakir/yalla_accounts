import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_book_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_deposit_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_maturity_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int clientId;
  late int arId;
  late int revenueId;
  late int supplierId;
  late int apId;
  late int bankAccountId;
  late String bookId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cheque_lifecycle_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'cheque-owner');

    clientId = await db.insert('clients', {
      'name': 'Lifecycle Customer',
      'type': 'individual',
    });
    arId = await db.insert('accounts', {
      'code': '1200.C$clientId',
      'name': 'Lifecycle Customer AR',
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

    supplierId = await db.insert('suppliers', {'name': 'Lifecycle Supplier'});
    apId = await db.insert('accounts', {
      'code': '2200.S${supplierId.toString().padLeft(4, '0')}',
      'name': 'Lifecycle Supplier AP',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT',
    });
    final expenseId = await db.insert('accounts', {
      'code': '5997.CHEQUE.LIFE',
      'name': 'Lifecycle purchase',
      'type': 'EXPENSE',
      'normal_balance': 'DEBIT',
    });
    await db.insert('purchase_invoices', {
      'id': 'PUR-LIFE',
      'supplier_id': supplierId,
      'amount_total': 10000.0,
      'paid_total': 0.0,
      'date': '2026-09-19',
      'method': 'credit',
      'status': 'UNPAID',
    });
    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 9, 19),
      source: 'PURCHASE',
      sourceId: 'PUR-LIFE',
      lines: [
        {
          'account_id': expenseId,
          'debit': 10000.0,
          'credit': 0.0,
          'invoice_id': 'PUR-LIFE',
        },
        {
          'account_id': apId,
          'debit': 0.0,
          'credit': 10000.0,
          'party_type': 'SUPPLIER',
          'party_id': supplierId,
          'invoice_id': 'PUR-LIFE',
        },
      ],
    );

    bankAccountId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1010'],
      limit: 1,
    ))
        .single['id'] as int;

    bookId = await db.transaction(
      (txn) => ChequeBookService.createOnTxn(
        txn: txn,
        bankAccountId: bankAccountId,
        bookNumber: 'LIFE-BOOK',
        firstChequeNumber: 200,
        lastChequeNumber: 220,
        createdBy: 'cheque-owner',
      ),
    );
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    await session.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
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

  Map<String, dynamic> receivedDraft(String key, double amount) => {
        'uuid': 'uuid-$key',
        'instrument_key': key,
        'cheque_no': 'R-$key',
        'drawer_name': 'Lifecycle Customer',
        'bank_name': 'Drawer Bank',
        'bank_branch': 'Bethlehem',
        'issue_date': '2026-09-19T00:00:00',
        'due_date': '2026-10-19T00:00:00',
        'amount': amount,
      };

  Future<int> receive({
    required String op,
    required String key,
    required String repairId,
    required double amount,
  }) async {
    await PaymentService.insertCanonicalReceiptWithInstruments(
      operationId: op,
      database: db,
      clientId: clientId,
      customerName: 'Lifecycle Customer',
      date: DateTime(2026, 9, 19),
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: key,
          method: 'cheque',
          amount: amount,
          chequeDraft: receivedDraft(key, amount),
          allocations: [
            ReceiptAllocationInput(repairId: repairId, amount: amount),
          ],
        ),
      ],
    );
    return (await db.query(
      'cheques',
      columns: const ['id'],
      where: 'instrument_key=?',
      whereArgs: [key],
      limit: 1,
    ))
        .single['id'] as int;
  }

  Map<String, dynamic> issuedDraft(int number, String key) => {
        'uuid': 'uuid-$key',
        'instrument_key': key,
        'cheque_no': '$number',
        'drawer_name': 'Yallah Workshop',
        'bank_name': 'Workshop Bank',
        'bank_branch': 'Bethlehem',
        'issue_date': '2026-09-19T00:00:00',
        'due_date': '2026-10-19T00:00:00',
        'bank_account_id': bankAccountId,
        'cheque_book_id': bookId,
      };

  VoucherPayment issuedVoucher(String id, double amount) => VoucherPayment(
        id: id,
        voucherType: 'PAYMENT',
        partyType: 'SUPPLIER',
        partyId: supplierId.toString(),
        amount: amount,
        currency: 'ILS',
        date: DateTime(2026, 9, 19),
        method: 'CHEQUE',
        reference: 'PUR-LIFE',
      );

  Future<int> issue({
    required String id,
    required int number,
    required double amount,
  }) async {
    final posted = await VoucherPaymentService.insertAndPost(
      voucher: issuedVoucher(id, amount),
      partyName: 'Lifecycle Supplier',
      chequeDraft: issuedDraft(number, 'issued-$number'),
      database: db,
    );
    return int.parse(posted.chequeId!);
  }

  Future<double> repairOutstanding(String id) async =>
      (await RepairFinancialTruthService.load(
        id,
        executor: db,
      ))
          .outstandingBalance;

  Future<double> supplierBalance() async {
    final rows = await PartyFinancialService.balances(executor: db);
    return rows
        .singleWhere((row) => row.supplierLegacyId == '$supplierId')
        .payableBalance;
  }

  Future<double> customerBalance() async {
    final rows = await PartyFinancialService.balances(executor: db);
    return rows
        .singleWhere((row) => row.customerLegacyId == '$clientId')
        .receivableBalance;
  }

  Future<double> accountNet(int id) async {
    final row = (await db.rawQuery(
      'SELECT COALESCE(SUM(debit-credit),0) n FROM gl_lines '
      'WHERE account_id=?',
      [id],
    ))
        .single;
    return (row['n'] as num).toDouble();
  }

  Future<void> expectBalancedSource(String source, String sourceId) async {
    final row = (await db.rawQuery(
      '''
      SELECT COALESCE(SUM(l.debit),0) d, COALESCE(SUM(l.credit),0) c
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      WHERE e.source=? AND e.source_id=?
      ''',
      [source, sourceId],
    ))
        .single;
    expect((row['d'] as num).toDouble(), (row['c'] as num).toDouble());
  }

  test('PHASE7 invalid received transition is blocked', () async {
    await createRepair('R-STATE', 1000);
    final chequeId = await receive(
      op: 'RCV-STATE',
      key: 'state',
      repairId: 'R-STATE',
      amount: 500,
    );

    await expectLater(
      ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.collected,
      ),
      throwsStateError,
    );
    final row = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
    ))
        .single;
    expect(row['status'], 'received');
    expect(
      await db.query(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['CHEQUE_STATUS'],
      ),
      isEmpty,
    );
  });

  test(
    'DEP-001/002 and COL-001/002 deposit is not collection and collection is idempotent',
    () async {
      await createRepair('R-DEP', 5000);
      final chequeId = await receive(
        op: 'RCV-DEP',
        key: 'dep',
        repairId: 'R-DEP',
        amount: 3000,
      );
      expect(await repairOutstanding('R-DEP'), 2000);
      final bankBefore = await accountNet(bankAccountId);

      final batch = await ChequeDepositService.depositBatch(
        batchId: 'DEP-BATCH-1',
        bankAccountId: bankAccountId,
        chequeIds: [chequeId],
        depositDate: DateTime(2026, 9, 20),
        database: db,
      );
      expect(batch, 'DEP-BATCH-1');

      var cheque = (await db.query(
        'cheques',
        where: 'id=?',
        whereArgs: [chequeId],
      ))
          .single;
      expect(cheque['status'], 'deposited');
      expect(cheque['deposited_at'], isNotNull);
      expect(cheque['collection_date'], isNull);
      expect(cheque['bank_account_id'], bankAccountId);
      expect(await accountNet(bankAccountId), bankBefore);
      expect(
        await db.query(
          'gl_entries',
          where: 'source=?',
          whereArgs: ['CHEQUE_STATUS'],
        ),
        isEmpty,
      );

      final batchRows = await db.query(
        'cheque_deposit_batches',
        where: 'id=?',
        whereArgs: ['DEP-BATCH-1'],
      );
      expect(batchRows.single['cheque_count'], 1);
      expect(batchRows.single['total_value'], 3000.0);
      expect(
        await db.query(
          'cheque_deposit_items',
          where: 'batch_id=?',
          whereArgs: ['DEP-BATCH-1'],
        ),
        hasLength(1),
      );

      final retry = await ChequeDepositService.depositBatch(
        batchId: 'DEP-BATCH-1',
        bankAccountId: bankAccountId,
        chequeIds: [chequeId],
        depositDate: DateTime(2026, 9, 20),
        database: db,
      );
      expect(retry, 'DEP-BATCH-1');
      expect(
        await db.query(
          'cheque_deposit_items',
          where: 'batch_id=?',
          whereArgs: ['DEP-BATCH-1'],
        ),
        hasLength(1),
      );

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.collected,
        eventDate: DateTime(2026, 9, 22),
      );
      cheque = (await db.query(
        'cheques',
        where: 'id=?',
        whereArgs: [chequeId],
      ))
          .single;
      expect(cheque['status'], 'collected');
      expect(cheque['collection_date'], isNotNull);
      expect(await accountNet(bankAccountId), bankBefore + 3000);
      expect(await repairOutstanding('R-DEP'), 2000);

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.collected,
        eventDate: DateTime(2026, 9, 22),
      );
      final statusEntries = await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['CHEQUE_STATUS', '$chequeId:collected'],
      );
      expect(statusEntries, hasLength(1));
      await expectBalancedSource('CHEQUE_STATUS', '$chequeId:collected');
    },
  );

  test(
    'RET-001/002 returned received cheque reopens repair and customer AR',
    () async {
      await createRepair('R-RET', 5000);
      final chequeId = await receive(
        op: 'RCV-RET',
        key: 'ret',
        repairId: 'R-RET',
        amount: 3000,
      );
      expect(await repairOutstanding('R-RET'), 2000);
      expect(await customerBalance(), 2000);

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.returned,
        reason: 'Insufficient funds',
        eventDate: DateTime(2026, 9, 25),
      );

      expect(await repairOutstanding('R-RET'), 5000);
      expect(await customerBalance(), 5000);
      final cheque = (await db.query(
        'cheques',
        where: 'id=?',
        whereArgs: [chequeId],
      ))
          .single;
      expect(cheque['status'], 'returned');
      expect(cheque['returned_at'], isNotNull);
      expect(cheque['return_reason'], 'Insufficient funds');
      expect(await db.query('payments'), isNotEmpty);
      expect(await db.query('receipt_headers'), isNotEmpty);
      await expectBalancedSource('CHEQUE_STATUS', '$chequeId:returned');
    },
  );

  test(
    'CAN-001/002 cancelling received cheque preserves history and reopens AR',
    () async {
      await createRepair('R-CAN', 2000);
      final chequeId = await receive(
        op: 'RCV-CAN',
        key: 'can',
        repairId: 'R-CAN',
        amount: 2000,
      );
      expect(await repairOutstanding('R-CAN'), 0);

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.cancelled,
        reason: 'Wrong physical cheque',
        eventDate: DateTime(2026, 9, 19),
      );
      expect(await repairOutstanding('R-CAN'), 2000);

      final cheque = (await db.query(
        'cheques',
        where: 'id=?',
        whereArgs: [chequeId],
      ))
          .single;
      expect(cheque['status'], 'cancelled');
      expect(cheque['cancelled_at'], isNotNull);
      expect(cheque['cancellation_reason'], 'Wrong physical cheque');
      expect(
        await db.query('cheques', where: 'id=?', whereArgs: [chequeId]),
        hasLength(1),
      );
      expect(
        await db.query(
          'cheque_events',
          where: 'cheque_id=? AND event_type=?',
          whereArgs: [chequeId, 'status:cancelled'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'issued delivered/presented/cleared keeps bank untouched until clear',
    () async {
      final chequeId = await issue(id: 'PV-CLEAR', number: 200, amount: 4000);
      expect(await supplierBalance(), 6000);
      final bankBefore = await accountNet(bankAccountId);

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.delivered,
        eventDate: DateTime(2026, 9, 20),
      );
      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.presented,
        eventDate: DateTime(2026, 10, 19),
      );
      expect(await accountNet(bankAccountId), bankBefore);
      expect(
        await db.query(
          'gl_entries',
          where: 'source=?',
          whereArgs: ['CHEQUE_STATUS'],
        ),
        isEmpty,
      );

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.cleared,
        eventDate: DateTime(2026, 10, 19),
      );
      expect(await accountNet(bankAccountId), bankBefore - 4000);
      expect(await supplierBalance(), 6000);
      final cheque = (await db.query(
        'cheques',
        where: 'id=?',
        whereArgs: [chequeId],
      ))
          .single;
      expect(cheque['status'], 'cleared');
      expect(cheque['delivered_at'], isNotNull);
      expect(cheque['presented_at'], isNotNull);
      expect(cheque['cleared_at'], isNotNull);

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.cleared,
      );
      expect(
        await db.query(
          'gl_entries',
          where: 'source=? AND source_id=?',
          whereArgs: ['CHEQUE_STATUS', '$chequeId:cleared'],
        ),
        hasLength(1),
      );
      await expectBalancedSource('CHEQUE_STATUS', '$chequeId:cleared');

      await expectLater(
        ChequeAccountingService.transitionStatus(
          chequeId: chequeId,
          newStatus: ChequeStatus.issued,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'issued cancellation restores supplier payable without deleting cheque',
    () async {
      final chequeId = await issue(id: 'PV-VOID', number: 200, amount: 4000);
      expect(await supplierBalance(), 6000);

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.cancelled,
        reason: 'Supplier agreement cancelled',
        eventDate: DateTime(2026, 9, 20),
      );
      expect(await supplierBalance(), 10000);
      final cheque = (await db.query(
        'cheques',
        where: 'id=?',
        whereArgs: [chequeId],
      ))
          .single;
      expect(cheque['status'], 'cancelled');
      expect(cheque['cancelled_at'], isNotNull);
      expect(
        await db.query('cheques', where: 'id=?', whereArgs: [chequeId]),
        hasLength(1),
      );
      await expectBalancedSource('CHEQUE_STATUS', '$chequeId:cancelled');
    },
  );

  test(
    'returned issued cheque restores supplier AP exactly once',
    () async {
      final chequeId = await issue(id: 'PV-RETURN', number: 200, amount: 4000);
      expect(await supplierBalance(), 6000);

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.delivered,
        eventDate: DateTime(2026, 9, 20),
      );
      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.returned,
        reason: 'Bank returned issued cheque',
        eventDate: DateTime(2026, 9, 25),
      );

      expect(await supplierBalance(), 10000);
      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.returned,
        reason: 'Retry after timeout',
      );
      expect(await supplierBalance(), 10000);
      expect(
        await db.query(
          'gl_entries',
          where: 'source=? AND source_id=?',
          whereArgs: ['CHEQUE_STATUS', '$chequeId:returned'],
        ),
        hasLength(1),
      );
      await expectBalancedSource('CHEQUE_STATUS', '$chequeId:returned');
    },
  );

  test(
    'PHASE12 endorsement preserves received direction and immutable chain',
    () async {
      await createRepair('R-END', 3000);
      final chequeId = await receive(
        op: 'RCV-END',
        key: 'endorse',
        repairId: 'R-END',
        amount: 3000,
      );
      expect(await repairOutstanding('R-END'), 0);
      expect(await supplierBalance(), 10000);

      final endorsed = await ChequeAccountingService.endorseToSupplier(
        chequeId: chequeId,
        supplierPid: supplierId.toString(),
        endorsementDate: DateTime(2026, 9, 21),
      );
      expect(endorsed.direction, ChequeDirection.received);
      expect(endorsed.status, ChequeStatus.endorsed);
      expect(await supplierBalance(), 7000);
      expect(
        await db.query(
          'cheque_endorsements',
          where: 'cheque_id=?',
          whereArgs: [chequeId],
        ),
        hasLength(1),
      );

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.returned,
        reason: 'Endorsed cheque returned',
        eventDate: DateTime(2026, 9, 24),
      );
      expect(await repairOutstanding('R-END'), 3000);
      expect(await supplierBalance(), 10000);
      expect(
        await db.query(
          'cheque_endorsements',
          where: 'cheque_id=?',
          whereArgs: [chequeId],
        ),
        hasLength(1),
      );
    },
  );

  test('PHASE14 due classifications are derived and terminal status wins', () {
    Cheque cheque(String status, String dueDate) => Cheque.fromMap({
          'id': 1,
          'uuid': 'maturity',
          'cheque_no': 'M-1',
          'cheque_type': 'incoming',
          'direction': 'RECEIVED',
          'status': status,
          'drawer_name': 'Drawer',
          'bank_name': 'Bank',
          'bank_branch': '',
          'amount': 100.0,
          'currency': 'ILS',
          'issue_date': '2026-09-01',
          'due_date': dueDate,
          'created_at': '2026-09-01',
          'updated_at': '2026-09-01',
        });

    final asOf = DateTime(2026, 9, 19);
    expect(
      ChequeMaturityService.classify(
        cheque('received', '2026-09-19'),
        asOf: asOf,
      ),
      ChequeMaturityClass.dueToday,
    );
    expect(
      ChequeMaturityService.classify(
        cheque('received', '2026-09-22'),
        asOf: asOf,
      ),
      ChequeMaturityClass.dueSoon,
    );
    expect(
      ChequeMaturityService.classify(
        cheque('received', '2026-10-19'),
        asOf: asOf,
      ),
      ChequeMaturityClass.postDated,
    );
    expect(
      ChequeMaturityService.classify(
        cheque('received', '2026-09-18'),
        asOf: asOf,
      ),
      ChequeMaturityClass.overdue,
    );
    expect(
      ChequeMaturityService.classify(
        cheque('collected', '2026-09-18'),
        asOf: asOf,
      ),
      ChequeMaturityClass.collected,
    );
    expect(
      ChequeMaturityService.isActionableDue(
        cheque('collected', '2026-09-18'),
        asOf: asOf,
      ),
      isFalse,
    );
    expect(
      ChequeMaturityService.isActionableDue(
        cheque('received', '2026-09-18'),
        asOf: asOf,
      ),
      isTrue,
    );
    expect(
      ChequeMaturityService.isActionableDue(
        cheque('received', '2026-09-22'),
        asOf: asOf,
      ),
      isTrue,
    );
  });

  test('collected incoming cheque cannot be cancelled after settlement', () async {
    await createRepair('R-COL-CAN', 2000);
    final chequeId = await receive(
      op: 'RCV-COL-CAN',
      key: 'col-can',
      repairId: 'R-COL-CAN',
      amount: 2000,
    );
    await ChequeDepositService.depositBatch(
      batchId: 'DEP-COL-CAN',
      bankAccountId: bankAccountId,
      chequeIds: [chequeId],
      depositDate: DateTime(2026, 9, 20),
      database: db,
    );
    await ChequeAccountingService.transitionStatus(
      chequeId: chequeId,
      newStatus: ChequeStatus.collected,
      eventDate: DateTime(2026, 9, 22),
    );

    final bankAfterCollection = await accountNet(bankAccountId);
    final arAfterCollection = await customerBalance();
    final statusEntriesBefore = await db.query(
      'gl_entries',
      where: 'source=?',
      whereArgs: ['CHEQUE_STATUS'],
    );

    await expectLater(
      ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.cancelled,
        reason: 'must not cancel settled cheque directly',
      ),
      throwsStateError,
    );

    final cheque = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
    ))
        .single;
    expect(cheque['status'], 'collected');
    expect(await accountNet(bankAccountId), bankAfterCollection);
    expect(await customerBalance(), arAfterCollection);
    expect(
      await db.query(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['CHEQUE_STATUS'],
      ),
      hasLength(statusEntriesBefore.length),
    );
  });
}
