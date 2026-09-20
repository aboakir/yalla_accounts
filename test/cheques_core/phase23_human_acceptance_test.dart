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
import 'package:yalla_accounts/features/cheques/services/cheque_trace_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PHASE23 FLOW 1→10 cheque acceptance survives restart', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final temp = await Directory.systemTemp.createTemp('cheque_acceptance_');
    final path = '${temp.path}/acceptance.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    DatabaseMigration.useDatabaseForTesting(db);
    var session = await startAccountingSession(db, 'acceptance-owner');
    await db.update('owner_bootstrap_state', {
      'status': 'COMPLETED',
      'owner_user_id': 'acceptance-owner',
      'completed_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    final clientId = await db.insert('clients', {
      'name': 'Acceptance Customer',
      'type': 'individual',
    });
    final arId = await db.insert('accounts', {
      'code': '1200.C$clientId',
      'name': 'Acceptance AR',
      'type': 'ASSET',
      'normal_balance': 'DEBIT',
    });
    await db.update(
      'clients',
      {'account_id': arId},
      where: 'id=?',
      whereArgs: [clientId],
    );
    final revenueId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['4000'],
      limit: 1,
    ))
        .single['id'] as int;
    final bankId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1010'],
      limit: 1,
    ))
        .single['id'] as int;
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

    Map<String, dynamic> receivedDraft(
      String key,
      double amount,
    ) =>
        {
          'uuid': 'uuid-$key',
          'instrument_key': key,
          'cheque_no': 'RCV-$key',
          'drawer_name': 'Acceptance Customer',
          'bank_name': 'Customer Bank',
          'bank_branch': 'Bethlehem',
          'issue_date': '2026-09-19T00:00:00',
          'due_date': '2026-09-25T00:00:00',
          'amount': amount,
        };

    Future<int> receive(
      String op,
      String key,
      String repairId,
      double amount,
    ) async {
      final receipt =
          await PaymentService.insertCanonicalReceiptWithInstruments(
        operationId: op,
        database: db,
        clientId: clientId,
        customerName: 'Acceptance Customer',
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
        where: 'receipt_voucher_id=?',
        whereArgs: [receipt.receiptNumber],
        orderBy: 'id DESC',
        limit: 1,
      ))
          .single['id'] as int;
    }

    Future<double> outstanding(String repairId) async =>
        (await RepairFinancialTruthService.load(repairId, executor: db))
            .outstandingBalance; // FLOW 1: customer owes 5,000 -> cheque 3,000 -> 2,000 remains.
    await createRepair('R-MAIN', 5000);
    final received3000 = await receive('FLOW-1', 'FLOW1-3000', 'R-MAIN', 3000);
    expect(await outstanding('R-MAIN'), 2000, reason: 'FLOW 1');

    // FLOW 2: second cheque 2,000 -> zero remains.
    final received2000 = await receive('FLOW-2', 'FLOW2-2000', 'R-MAIN', 2000);
    expect(await outstanding('R-MAIN'), 0, reason: 'FLOW 2');

    Future<double> bankNet() async {
      final row = (await db.rawQuery(
        'SELECT COALESCE(SUM(debit-credit),0) n '
        'FROM gl_lines WHERE account_id=?',
        [bankId],
      ))
          .single;
      return (row['n'] as num).toDouble();
    }

    // FLOW 3: deposit does not mean collection.
    final bankBeforeDeposit = await bankNet();
    await ChequeDepositService.depositBatch(
      batchId: 'FLOW-3-BATCH',
      bankAccountId: bankId,
      chequeIds: [received3000],
      depositDate: DateTime(2026, 9, 20),
      database: db,
    );
    var row = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [received3000],
    ))
        .single;
    expect(row['status'], 'deposited', reason: 'FLOW 3');
    expect(row['collection_date'], isNull, reason: 'FLOW 3');
    expect(await bankNet(), bankBeforeDeposit, reason: 'FLOW 3');

    // FLOW 4: collection happens explicitly.
    await ChequeAccountingService.transitionStatus(
      chequeId: received3000,
      newStatus: ChequeStatus.collected,
      eventDate: DateTime(2026, 9, 21),
    );
    row = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [received3000],
    ))
        .single;
    expect(row['status'], 'collected', reason: 'FLOW 4');
    expect(await bankNet(), bankBeforeDeposit + 3000, reason: 'FLOW 4');

    // FLOW 5: returned received cheque reopens receivable.
    await createRepair('R-RETURN', 3000);
    final returnedCheque =
        await receive('FLOW-5', 'FLOW5-RETURN', 'R-RETURN', 3000);
    expect(await outstanding('R-RETURN'), 0);
    await ChequeAccountingService.transitionStatus(
      chequeId: returnedCheque,
      newStatus: ChequeStatus.returned,
      reason: 'Bank returned cheque',
      eventDate: DateTime(2026, 9, 22),
    );
    expect(await outstanding('R-RETURN'), 3000,
        reason: 'FLOW 5'); // Supplier/AP setup for FLOW 6-8.
    final supplierId =
        await db.insert('suppliers', {'name': 'Acceptance Supplier'});
    final apId = await db.insert('accounts', {
      'code': '2200.S${supplierId.toString().padLeft(4, '0')}',
      'name': 'Acceptance Supplier AP',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT',
    });
    final expenseId = await db.insert('accounts', {
      'code': '5996.CHEQUE.ACCEPT',
      'name': 'Acceptance purchase',
      'type': 'EXPENSE',
      'normal_balance': 'DEBIT',
    });
    await db.insert('purchase_invoices', {
      'id': 'PUR-10000',
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
      sourceId: 'PUR-10000',
      lines: [
        {
          'account_id': expenseId,
          'debit': 10000.0,
          'credit': 0.0,
          'invoice_id': 'PUR-10000',
        },
        {
          'account_id': apId,
          'debit': 0.0,
          'credit': 10000.0,
          'party_type': 'SUPPLIER',
          'party_id': supplierId,
          'invoice_id': 'PUR-10000',
        },
      ],
    );

    final bookId = await db.transaction(
      (txn) => ChequeBookService.createOnTxn(
        txn: txn,
        bankAccountId: bankId,
        bookNumber: 'ACCEPT-BOOK',
        firstChequeNumber: 500,
        lastChequeNumber: 510,
        createdBy: 'acceptance-owner',
      ),
    );

    Map<String, dynamic> issuedDraft(int number) => {
          'uuid': 'issued-$number',
          'instrument_key': 'issued-$number',
          'cheque_no': '$number',
          'drawer_name': 'Yallah Workshop',
          'bank_name': 'Workshop Bank',
          'bank_branch': 'Bethlehem',
          'issue_date': '2026-09-19T00:00:00',
          'due_date': '2026-10-19T00:00:00',
          'bank_account_id': bankId,
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
          reference: 'PUR-10000',
        );

    Future<double> supplierBalance() async {
      final balances = await PartyFinancialService.balances(executor: db);
      return balances
          .singleWhere((r) => r.supplierLegacyId == '$supplierId')
          .payableBalance;
    } // FLOW 6: supplier owes 10,000 -> issued cheque 4,000 -> 6,000.

    await VoucherPaymentService.insertAndPost(
      voucher: issuedVoucher('FLOW-6-PV', 4000),
      partyName: 'Acceptance Supplier',
      chequeDraft: issuedDraft(500),
      database: db,
    );
    expect(await supplierBalance(), 6000, reason: 'FLOW 6');

    // FLOW 7: second issued cheque 6,000 -> zero.
    final issued6000 = await VoucherPaymentService.insertAndPost(
      voucher: issuedVoucher('FLOW-7-PV', 6000),
      partyName: 'Acceptance Supplier',
      chequeDraft: issuedDraft(501),
      database: db,
    );
    expect(await supplierBalance(), 0, reason: 'FLOW 7');

    // FLOW 8: cancel second issued cheque -> AP restored by 6,000.
    await ChequeAccountingService.transitionStatus(
      chequeId: int.parse(issued6000.chequeId!),
      newStatus: ChequeStatus.cancelled,
      reason: 'Cancelled before delivery',
      eventDate: DateTime(2026, 9, 20),
    );
    expect(await supplierBalance(), 6000, reason: 'FLOW 8');
    final cancelled = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [int.parse(issued6000.chequeId!)],
    ))
        .single;
    expect(cancelled['status'], 'cancelled', reason: 'FLOW 8');

    // FLOW 9: cheque number -> voucher -> party -> repair/invoice -> GL.
    final search = await ChequeTraceService.search(
      'RCV-FLOW1-3000',
      executor: db,
    );
    expect(search.map((c) => c.id), contains(received3000), reason: 'FLOW 9');
    final trace = await ChequeTraceService.load(received3000, executor: db);
    expect(trace.voucherLinks, hasLength(1), reason: 'FLOW 9');
    expect(trace.parties.single['name'], 'Acceptance Customer',
        reason: 'FLOW 9');
    expect(
      trace.allocations.map((a) => a['target_id']),
      contains('R-MAIN'),
      reason: 'FLOW 9',
    );
    expect(
      trace.glEntries.map((g) => g['invoice_id']),
      contains('INV-R-MAIN'),
      reason: 'FLOW 9',
    );
    expect(trace.glEntries, isNotEmpty,
        reason: 'FLOW 9'); // Capture expected truth before restart.
    final expectedMainOutstanding = await outstanding('R-MAIN');
    final expectedReturnOutstanding = await outstanding('R-RETURN');
    final expectedSupplier = await supplierBalance();
    final expectedBank = await bankNet();

    // FLOW 10: restart DB, truth persists.
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();

    db = await DatabaseMigration.initDatabase(pathOverride: path);
    DatabaseMigration.useDatabaseForTesting(db);

    final collectedAfter = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [received3000],
    ))
        .single;
    final secondReceivedAfter = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [received2000],
    ))
        .single;
    final returnedAfter = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [returnedCheque],
    ))
        .single;
    final cancelledAfter = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [int.parse(issued6000.chequeId!)],
    ))
        .single;

    expect(collectedAfter['status'], 'collected', reason: 'FLOW 10');
    expect(secondReceivedAfter['status'], 'received', reason: 'FLOW 10');
    expect(returnedAfter['status'], 'returned', reason: 'FLOW 10');
    expect(cancelledAfter['status'], 'cancelled', reason: 'FLOW 10');

    Future<double> outstandingAfter(String repairId) async =>
        (await RepairFinancialTruthService.load(repairId, executor: db))
            .outstandingBalance;
    Future<double> supplierAfter() async {
      final balances = await PartyFinancialService.balances(executor: db);
      return balances
          .singleWhere((r) => r.supplierLegacyId == '$supplierId')
          .payableBalance;
    }

    Future<double> bankAfter() async {
      final item = (await db.rawQuery(
        'SELECT COALESCE(SUM(debit-credit),0) n FROM gl_lines WHERE account_id=?',
        [bankId],
      ))
          .single;
      return (item['n'] as num).toDouble();
    }

    expect(await outstandingAfter('R-MAIN'), expectedMainOutstanding,
        reason: 'FLOW 10');
    expect(await outstandingAfter('R-RETURN'), expectedReturnOutstanding,
        reason: 'FLOW 10');
    expect(await supplierAfter(), expectedSupplier, reason: 'FLOW 10');
    expect(await bankAfter(), expectedBank, reason: 'FLOW 10');

    expect(
      await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['CHEQUE_STATUS', '$received3000:collected'],
      ),
      hasLength(1),
      reason: 'FLOW 10 no duplicate collection',
    );
    expect(
      await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: [
          'CHEQUE_STATUS',
          '${int.parse(issued6000.chequeId!)}:cancelled'
        ],
      ),
      hasLength(1),
      reason: 'FLOW 10 no duplicate cancellation',
    );

    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();
    await temp.delete(recursive: true);
  });
}
