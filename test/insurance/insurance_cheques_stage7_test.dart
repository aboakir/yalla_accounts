import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_book_service.dart';
import 'package:yalla_accounts/features/insurance_agent/alerts/services/insurance_alert_center_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_policy_cashflow_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late String policyId;
  late int bankAccountId;
  late String bookId;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_stage7_cheques_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/stage7.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'insurance-stage7-owner');

    final clientId = await db.insert('clients', {
      'name': 'Stage 7 Customer',
      'type': 'individual',
      'phone': '0599777100',
    });
    final clientPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['CUSTOMER', clientId.toString()],
      limit: 1,
    ))
        .single['party_id']
        .toString();
    final now = DateTime(2026, 9, 23).toIso8601String();
    await db.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': now,
    });

    final supplierId = await db.insert('suppliers', {
      'name': 'Stage 7 Insurance Company',
      'pid': 'S-STAGE7',
    });
    final supplierPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['SUPPLIER', supplierId.toString()],
      limit: 1,
    ))
        .single['party_id']
        .toString();
    final companyId = await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'STAGE7-INS',
      'name': 'Stage 7 Insurance Company',
      'default_commission_rate': 0.0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('party_roles', {
      'party_id': supplierPartyId,
      'role': 'INSURANCE_COMPANY',
      'legacy_id': companyId.toString(),
      'created_at': now,
    });

    final policy = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'STAGE7-POLICY',
        policyNumber: 'STAGE7-POL-001',
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId.toString(),
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 23),
        endDate: DateTime(2027, 9, 22),
        postingDate: DateTime(2026, 9, 23),
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'insurance-stage7-owner',
      ),
      database: db,
    );
    policyId = policy.policyId;

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
        bookNumber: 'INS-STAGE7',
        firstChequeNumber: 100,
        lastChequeNumber: 102,
        createdBy: 'insurance-stage7-owner',
      ),
    );
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<double> accountBalance(String code) async {
    final account = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    ))
        .single['id'];
    final row = (await db.rawQuery(
      'SELECT COALESCE(SUM(debit-credit),0) n FROM gl_lines WHERE account_id=?',
      [account],
    ))
        .single;
    return (row['n'] as num).toDouble();
  }

  test('insurer cheque reserves book number and stays linked to voucher',
      () async {
    final books = await InsurancePolicyCashflowService.listOpenChequeBooks(
      executor: db,
    );
    expect(books, hasLength(1));
    expect(books.single.id, bookId);
    expect(books.single.nextAvailableNumber, 100);

    await InsurancePolicyCashflowService.payInsurerByCheque(
      operationId: 'STAGE7-OUT-100',
      policyId: policyId,
      amount: 700,
      issueDate: DateTime(2026, 9, 23),
      dueDate: DateTime(2026, 10, 23),
      chequeBookId: bookId,
      notes: 'canonical outgoing insurance cheque',
      database: db,
    );

    final cheques = await db.query('cheques');
    expect(cheques, hasLength(1));
    final cheque = cheques.single;
    expect(cheque['direction'], 'ISSUED');
    expect(cheque['status'], 'issued');
    expect(cheque['cheque_no'], '100');
    expect(cheque['bank_account_id'], bankAccountId);
    expect(cheque['cheque_book_id'], bookId);
    expect(cheque['payment_voucher_id'], isNotNull);

    final book = (await db.query(
      'cheque_books',
      where: 'id=?',
      whereArgs: [bookId],
      limit: 1,
    ))
        .single;
    expect(book['next_available_number'], 101);

    var snapshot = await InsurancePolicyCashflowService.load(
      policyId,
      executor: db,
    );
    expect(snapshot.balances.insurerPayments, 700);
    expect(snapshot.balances.insurerOutstanding, 1300);
    final movement = snapshot.movements.single;
    expect(movement.method, 'CHEQUE');
    expect(movement.chequeNumber, '100');
    expect(movement.chequeStatus, 'issued');
    expect(movement.chequeDirection, 'ISSUED');
    expect(movement.chequeDueDate, DateTime(2026, 10, 23));
    expect(movement.canReverse, isTrue);

    await InsurancePolicyCashflowService.reverseMovement(
      movement: movement,
      reason: 'Cancel outgoing insurer cheque',
      database: db,
    );

    final cancelled = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [cheque['id']],
      limit: 1,
    ))
        .single;
    expect(cancelled['status'], 'cancelled');
    snapshot = await InsurancePolicyCashflowService.load(
      policyId,
      executor: db,
    );
    expect(snapshot.balances.insurerPayments, 0);
    expect(snapshot.balances.insurerOutstanding, 2000);
    expect(snapshot.movements.single.status, 'REVERSED');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('clearing insurer cheque does not pay insurer twice', () async {
    await InsurancePolicyCashflowService.payInsurerByCheque(
      operationId: 'STAGE13-CLEAR-700',
      policyId: policyId,
      amount: 700,
      issueDate: DateTime(2026, 9, 23),
      dueDate: DateTime(2026, 10, 23),
      chequeBookId: bookId,
      notes: 'stage 13 canonical outgoing cheque',
      database: db,
    );

    final cheque = (await db.query('cheques')).single;
    final chequeId = (cheque['id'] as num).toInt();
    final voucherId = cheque['payment_voucher_id'].toString();

    expect(await accountBalance('1030'), -700);
    expect(await accountBalance('1010'), 0);
    expect(
      await db.query(
        'insurance_policy_payments',
        where: 'policy_id=? AND direction=? AND status=?',
        whereArgs: [policyId, 'INSURER_PAYMENT', 'POSTED'],
      ),
      hasLength(1),
    );
    expect(
      (await InsurancePolicyCashflowService.load(policyId, executor: db))
          .balances
          .insurerOutstanding,
      1300,
    );

    await ChequeAccountingService.transitionStatus(
      chequeId: chequeId,
      newStatus: ChequeStatus.delivered,
      eventDate: DateTime(2026, 9, 25),
    );
    await ChequeAccountingService.transitionStatus(
      chequeId: chequeId,
      newStatus: ChequeStatus.presented,
      eventDate: DateTime(2026, 10, 22),
    );
    await ChequeAccountingService.transitionStatus(
      chequeId: chequeId,
      newStatus: ChequeStatus.cleared,
      eventDate: DateTime(2026, 10, 23),
    );

    expect(await accountBalance('1030'), 0);
    expect(await accountBalance('1010'), -700);
    expect(
      await db.query(
        'insurance_policy_payments',
        where: 'policy_id=? AND direction=? AND status=?',
        whereArgs: [policyId, 'INSURER_PAYMENT', 'POSTED'],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'vouchers',
        where: 'id=?',
        whereArgs: [voucherId],
      ),
      hasLength(1),
    );
    expect(
      (await InsurancePolicyCashflowService.load(policyId, executor: db))
          .balances
          .insurerOutstanding,
      1300,
    );
    expect(
      await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['CHEQUE_STATUS', '$chequeId:cleared'],
      ),
      hasLength(1),
    );
  });

  test('returned incoming cheque reopens AR and remains a high alert',
      () async {
    await InsurancePolicyCashflowService.collectCustomer(
      operationId: 'STAGE7-IN-400',
      policyId: policyId,
      amount: 400,
      date: DateTime(2026, 9, 23),
      method: 'CHEQUE',
      chequeDraft: {
        'cheque_no': 'IN-STAGE7-400',
        'drawer_name': 'Stage 7 Customer',
        'bank_name': 'Customer Bank',
        'issue_date': DateTime(2026, 9, 23).toIso8601String(),
        'due_date': DateTime(2026, 10, 1).toIso8601String(),
      },
      database: db,
    );

    var snapshot = await InsurancePolicyCashflowService.load(
      policyId,
      executor: db,
    );
    final movement = snapshot.movements.single;
    expect(movement.chequeNumber, 'IN-STAGE7-400');
    expect(movement.chequeStatus, 'received');
    expect(movement.chequeDirection, 'RECEIVED');
    expect(movement.chequeBankName, 'Customer Bank');
    expect(snapshot.balances.customerOutstanding, 2000);

    final before = await InsuranceAlertCenterService.listAlerts(
      asOf: DateTime(2026, 9, 23),
      window: InsuranceAlertWindow.next30,
      executor: db,
    );
    expect(
      before.where(
        (alert) =>
            alert.type == 'CHEQUE_DUE' &&
            alert.policyId == policyId &&
            alert.sourceId == movement.chequeId.toString(),
      ),
      hasLength(1),
    );

    await ChequeAccountingService.transitionStatus(
      chequeId: movement.chequeId!,
      newStatus: ChequeStatus.returned,
      reason: 'Customer cheque returned',
      eventDate: DateTime(2026, 9, 24),
    );

    snapshot = await InsurancePolicyCashflowService.load(
      policyId,
      executor: db,
    );
    expect(snapshot.balances.customerReceipts, 0);
    expect(snapshot.balances.customerOutstanding, 2400);
    expect(snapshot.movements.single.status, 'REVERSED');
    expect(snapshot.movements.single.chequeStatus, 'returned');

    final alerts = await InsuranceAlertCenterService.listAlerts(
      asOf: DateTime(2026, 9, 24),
      window: InsuranceAlertWindow.next30,
      executor: db,
    );
    final returned = alerts.where(
      (alert) =>
          alert.type == 'RETURNED_CHEQUE' &&
          alert.policyId == policyId &&
          alert.sourceId == movement.chequeId.toString(),
    );
    expect(returned, hasLength(1));
    expect(returned.single.severity, 'HIGH');
  });
}
