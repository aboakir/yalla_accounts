import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_book_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int supplierId;
  late int bankAccountId;
  late int apId;
  late String bookId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('issued_cheques_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'cheque-owner');
    supplierId = await db.insert('suppliers', {'name': 'Cheque Supplier'});
    bankAccountId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1010'],
      limit: 1,
    ))
        .single['id'] as int;
    apId = await db.insert('accounts', {
      'code': '2200.S${supplierId.toString().padLeft(4, '0')}',
      'name': 'Cheque Supplier AP',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT',
    });
    final expenseId = await db.insert('accounts', {
      'code': '5998.CHEQUE.TEST',
      'name': 'Cheque test purchase',
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

    bookId = await db.transaction(
      (txn) => ChequeBookService.createOnTxn(
        txn: txn,
        bankAccountId: bankAccountId,
        bookNumber: 'BOOK-A',
        firstChequeNumber: 100,
        lastChequeNumber: 105,
        createdBy: 'cheque-owner',
      ),
    );
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  Map<String, dynamic> draft(int number, String key) => {
        'uuid': 'uuid-$key',
        'instrument_key': key,
        'cheque_no': number.toString(),
        'drawer_name': 'Yallah Workshop',
        'bank_name': 'Palestine Bank',
        'bank_branch': 'Bethlehem',
        'issue_date': '2026-09-19T00:00:00',
        'due_date': '2026-10-19T00:00:00',
        'bank_account_id': bankAccountId,
        'cheque_book_id': bookId,
      };

  VoucherPayment voucher(String id, double amount) => VoucherPayment(
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
    final rows = await PartyFinancialService.balances(executor: db);
    return rows
        .singleWhere((row) => row.supplierLegacyId == '$supplierId')
        .payableBalance;
  }

  test(
      'ISS-001..006 issued cheque links voucher supplier invoice bank and book',
      () async {
    final posted = await VoucherPaymentService.insertAndPost(
      voucher: voucher('PV-4000', 4000),
      partyName: 'Cheque Supplier',
      chequeDraft: draft(100, 'issued-100'),
      database: db,
    );

    expect(posted.chequeId, isNotNull);
    expect(await supplierBalance(), 6000);

    final cheque = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [int.parse(posted.chequeId!)],
    ))
        .single;
    expect(cheque['direction'], 'ISSUED');
    expect(cheque['status'], 'issued');
    expect(cheque['recipient_name'], 'Cheque Supplier');
    expect(cheque['bank_account_id'], bankAccountId);
    expect(cheque['cheque_book_id'], bookId);
    expect(cheque['payment_voucher_id'], 'PV-4000');

    final links = await db.query(
      'cheque_voucher_links',
      where: 'cheque_id=?',
      whereArgs: [cheque['id']],
    );
    expect(links, hasLength(1));
    expect(links.single['voucher_type'], 'PAYMENT');
    expect(links.single['voucher_id'], 'PV-4000');

    final allocations = await db.query(
      'cheque_allocations',
      where: 'cheque_id=?',
      whereArgs: [cheque['id']],
    );
    expect(allocations, hasLength(1));
    expect(allocations.single['allocation_type'], 'PURCHASE_INVOICE');
    expect(allocations.single['target_id'], 'PUR-10000');
    expect(allocations.single['amount'], 4000.0);

    final bankBalance = (await db.rawQuery(
      'SELECT COALESCE(SUM(l.debit-l.credit),0) n '
      'FROM gl_lines l WHERE l.account_id=?',
      [bankAccountId],
    ))
        .single['n'] as num;
    expect(bankBalance.toDouble(), 0);

    final outgoingAccount = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1030'],
      limit: 1,
    ))
        .single['id'] as int;
    final chequePayableBalance = (await db.rawQuery(
      'SELECT COALESCE(SUM(credit-debit),0) n FROM gl_lines '
      'WHERE account_id=?',
      [outgoingAccount],
    ))
        .single['n'] as num;
    expect(chequePayableBalance.toDouble(), 4000);
  });

  test('ISS partial then final issued cheques settle supplier payable',
      () async {
    await VoucherPaymentService.insertAndPost(
      voucher: voucher('PV-A', 4000),
      partyName: 'Cheque Supplier',
      chequeDraft: draft(100, 'issued-a'),
      database: db,
    );
    expect(await supplierBalance(), 6000);

    await VoucherPaymentService.insertAndPost(
      voucher: voucher('PV-B', 6000),
      partyName: 'Cheque Supplier',
      chequeDraft: draft(101, 'issued-b'),
      database: db,
    );
    expect(await supplierBalance(), 0);
    expect(await db.query('cheques'), hasLength(2));

    final settlements = await db.query(
      'invoice_settlements',
      where: 'invoice_id=?',
      whereArgs: ['PUR-10000'],
    );
    expect(
      settlements.fold<double>(
        0,
        (sum, row) => sum + (row['amount_applied'] as num).toDouble(),
      ),
      10000,
    );
  });

  test('ISS-007 duplicate or reused cheque number is blocked atomically',
      () async {
    await VoucherPaymentService.insertAndPost(
      voucher: voucher('PV-ONE', 1000),
      partyName: 'Cheque Supplier',
      chequeDraft: draft(100, 'first'),
      database: db,
    );

    await expectLater(
      VoucherPaymentService.insertAndPost(
        voucher: voucher('PV-DUP', 1000),
        partyName: 'Cheque Supplier',
        chequeDraft: draft(100, 'duplicate'),
        database: db,
      ),
      throwsA(anything),
    );

    expect(
      await db.query('vouchers', where: 'id=?', whereArgs: ['PV-DUP']),
      isEmpty,
    );
    expect(
      await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['VOUCHER', 'PV-DUP'],
      ),
      isEmpty,
    );
  });

  test('PHASE6 cancelled cheque number is never reused', () async {
    await VoucherPaymentService.insertAndPost(
      voucher: voucher('PV-CANCEL', 1000),
      partyName: 'Cheque Supplier',
      chequeDraft: draft(100, 'cancelled-number'),
      database: db,
    );
    await db.update(
      'cheques',
      {'status': 'cancelled'},
      where: 'cheque_book_id=? AND cheque_no=?',
      whereArgs: [bookId, '100'],
    );

    await expectLater(
      db.transaction(
        (txn) => ChequeBookService.reserveNumberOnTxn(
          txn: txn,
          bookId: bookId,
          requestedNumber: 100,
          allowOverride: true,
        ),
      ),
      throwsA(anything),
    );
  });

  test('PHASE6 outside-range and manual skip without permission are blocked',
      () async {
    await expectLater(
      db.transaction(
        (txn) => ChequeBookService.reserveNumberOnTxn(
          txn: txn,
          bookId: bookId,
          requestedNumber: 999,
          allowOverride: true,
        ),
      ),
      throwsA(anything),
    );
    await expectLater(
      db.transaction(
        (txn) => ChequeBookService.reserveNumberOnTxn(
          txn: txn,
          bookId: bookId,
          requestedNumber: 102,
        ),
      ),
      throwsA(anything),
    );
    expect(await ChequeBookService.nextAvailableNumber(db, bookId), 100);
  });
}
