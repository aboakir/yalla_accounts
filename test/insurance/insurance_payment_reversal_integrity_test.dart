import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int clientId;
  late int supplierId;
  late String clientPartyId;
  late String supplierPartyId;
  late String companyId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_reversals_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'insurance-reversal-owner');

    clientId = await db.insert('clients', {
      'name': 'Insurance Reversal Customer',
      'type': 'individual',
      'phone': '0599111222',
    });
    clientPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['CUSTOMER', clientId.toString()],
      limit: 1,
    ))
        .single['party_id']
        .toString();
    await db.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': DateTime.now().toIso8601String(),
    });

    supplierId = await db.insert('suppliers', {
      'name': 'Insurance Reversal Company',
      'pid': 'S-INS-REVERSAL',
    });
    supplierPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['SUPPLIER', supplierId.toString()],
      limit: 1,
    ))
        .single['party_id']
        .toString();
    final now = DateTime.now().toIso8601String();
    companyId = (await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'INS-REVERSAL',
      'name': 'Insurance Reversal Company',
      'default_commission_rate': 0.0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    }))
        .toString();
    await db.insert('party_roles', {
      'party_id': supplierPartyId,
      'role': 'INSURANCE_COMPANY',
      'legacy_id': companyId,
      'created_at': now,
    });
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<InsurancePolicyPostingResult> issue(String suffix) {
    return InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'REVERSAL-POLICY-$suffix',
        policyNumber: 'INSURER-REVERSAL-$suffix',
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId,
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 22),
        endDate: DateTime(2027, 9, 21),
        postingDate: DateTime(2026, 9, 22),
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'insurance-reversal-owner',
      ),
      database: db,
    );
  }

  Future<double> accountBalance(String code) async {
    final accountId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    ))
        .single['id'];
    final row = (await db.rawQuery(
      'SELECT COALESCE(SUM(debit-credit),0) amount '
      'FROM gl_lines WHERE account_id=?',
      [accountId],
    ))
        .single;
    return (row['amount'] as num).toDouble();
  }

  Future<int> count(String table) async {
    final row = (await db.rawQuery('SELECT COUNT(*) count FROM $table')).single;
    return (row['count'] as num).toInt();
  }

  Future<void> expectBalancedGl() async {
    final row = (await db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) debit, '
      'COALESCE(SUM(credit),0) credit FROM gl_lines',
    ))
        .single;
    expect(
      (row['debit'] as num).toDouble(),
      closeTo((row['credit'] as num).toDouble(), 0.001),
    );
  }

  test('insurance receipt normalizes every instrument before all posting',
      () async {
    final policy = await issue('ROUNDING');
    final receipt = await InsuranceFinancialService.collectPolicy(
      operationId: 'REVERSAL-ROUNDING-RECEIPT',
      policyId: policy.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'fraction-a',
          method: 'cash',
          amount: 1200.004,
        ),
        ReceiptInstrumentInput(
          instrumentKey: 'fraction-b',
          method: 'cash',
          amount: 1200.004,
        ),
      ],
    );

    final retry = await InsuranceFinancialService.collectPolicy(
      operationId: 'REVERSAL-ROUNDING-RECEIPT',
      policyId: policy.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'fraction-a',
          method: 'cash',
          amount: 1200.001,
        ),
        ReceiptInstrumentInput(
          instrumentKey: 'fraction-b',
          method: 'cash',
          amount: 1200.001,
        ),
      ],
    );
    expect(retry.receiptNumber, receipt.receiptNumber);
    expect(receipt.allocatedAmount, 2400);
    expect(await count('receipt_headers'), 1);

    final header = (await db.query('receipt_headers')).single;
    expect((header['total_amount'] as num).toDouble(), 2400);
    expect((header['allocated_amount'] as num).toDouble(), 2400);
    final paymentSum = (await db.rawQuery(
      'SELECT SUM(amount) amount FROM payments WHERE receipt_number=?',
      [receipt.receiptNumber],
    ))
        .single['amount'] as num;
    final linkSum = (await db.rawQuery(
      'SELECT SUM(amount) amount FROM insurance_policy_payments '
      'WHERE receipt_number=?',
      [receipt.receiptNumber],
    ))
        .single['amount'] as num;
    expect(paymentSum.toDouble(), 2400);
    expect(linkSum.toDouble(), 2400);

    final balances = await InsuranceFinancialService.balances(
      policy.policyId,
      executor: db,
    );
    expect(balances.customerReceipts, 2400);
    expect(balances.customerOutstanding, 0);
    expect(await accountBalance('1000'), 2400);
    expect(await accountBalance('1200.C$clientId'), 0);
    await expectBalancedGl();

    await expectLater(
      InsuranceFinancialService.collectPolicy(
        operationId: 'REVERSAL-ROUNDING-ZERO',
        policyId: policy.policyId,
        date: DateTime(2026, 9, 22),
        database: db,
        instruments: const [
          ReceiptInstrumentInput(
            instrumentKey: 'rounds-to-zero',
            method: 'cash',
            amount: 0.004,
          ),
        ],
      ),
      throwsStateError,
    );
    expect(await count('receipt_headers'), 1);
  });

  test('cash receipt reversal restores policy balance once and audits link',
      () async {
    final policy = await issue('CASH');
    final authorization = await PaymentService.preauthorizeInsuranceReceipt(
      includesCheque: false,
    );
    final receipt = await db.transaction(
      (txn) => PaymentService.insertCanonicalInsuranceReceipt(
        operationId: 'REVERSAL-CASH-RECEIPT',
        policyId: policy.policyId,
        date: DateTime(2026, 9, 22),
        database: txn,
        authorizationToken: authorization,
        instruments: const [
          ReceiptInstrumentInput(
            instrumentKey: 'cash-600',
            method: 'cash',
            amount: 600,
          ),
        ],
      ),
    );
    await expectLater(
      db.transaction(
        (txn) => PaymentService.insertCanonicalInsuranceReceipt(
          operationId: 'REVERSAL-CASH-RECEIPT',
          policyId: policy.policyId,
          date: DateTime(2026, 9, 22),
          database: txn,
          authorizationToken: authorization,
          instruments: const [
            ReceiptInstrumentInput(
              instrumentKey: 'cash-600',
              method: 'cash',
              amount: 600,
            ),
          ],
        ),
      ),
      throwsStateError,
    );

    await PaymentService.reverseReceipt(
      receipt.receiptNumber,
      reason: 'Insurance cash correction',
      database: db,
    );

    final link = (await db.query('insurance_policy_payments')).single;
    expect(link['status'], 'REVERSED');
    expect(link['reversal_payment_id'], isNotNull);
    expect(link['reversal_gl_entry_id'], isNotNull);
    expect(link['reversed_at'], isNotNull);
    expect(link['reversal_reason'], 'Insurance cash correction');
    final balances = await InsuranceFinancialService.balances(
      policy.policyId,
      executor: db,
    );
    expect(balances.customerReceipts, 0);
    expect(balances.customerOutstanding, 2400);
    expect(await accountBalance('1000'), 0);
    expect(await accountBalance('1200.C$clientId'), 2400);
    await expectBalancedGl();

    final glCount = await count('gl_entries');
    await expectLater(
      PaymentService.reverseReceipt(
        receipt.receiptNumber,
        reason: 'Duplicate retry',
        database: db,
      ),
      throwsStateError,
    );
    expect(await count('gl_entries'), glCount);
    expect(
      await db.query(
        'app_audit_events',
        where: 'action=?',
        whereArgs: ['RECEIPT_REVERSED'],
      ),
      hasLength(1),
    );
  });

  test('incoming cheque receipt reversal cancels cheque and restores AR once',
      () async {
    final policy = await issue('CHEQUE');
    final receipt = await InsuranceFinancialService.collectPolicy(
      operationId: 'REVERSAL-CHEQUE-RECEIPT',
      policyId: policy.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: 'cheque-700',
          method: 'cheque',
          amount: 700,
          chequeDraft: {
            'cheque_no': 'REV-CHQ-700',
            'drawer_name': 'Insurance Reversal Customer',
            'bank_name': 'Reversal Bank',
            'issue_date': DateTime(2026, 9, 22).toIso8601String(),
            'due_date': DateTime(2026, 12, 22).toIso8601String(),
          },
        ),
      ],
    );
    expect(await accountBalance('1020'), 700);

    await PaymentService.reverseReceipt(
      receipt.receiptNumber,
      reason: 'Insurance cheque correction',
      database: db,
    );

    final cheque = (await db.query('cheques')).single;
    expect(cheque['status'], 'cancelled');
    expect(cheque['cancellation_reason'], 'Insurance cheque correction');
    final link = (await db.query('insurance_policy_payments')).single;
    expect(link['status'], 'REVERSED');
    expect(link['cheque_id'], cheque['id']);
    expect(link['reversal_payment_id'], isNotNull);
    expect(link['reversal_gl_entry_id'], isNotNull);
    final balances = await InsuranceFinancialService.balances(
      policy.policyId,
      executor: db,
    );
    expect(balances.customerReceipts, 0);
    expect(balances.customerOutstanding, 2400);
    expect(await accountBalance('1020'), 0);
    expect(await accountBalance('1200.C$clientId'), 2400);
    await expectBalancedGl();

    final eventCount = await count('cheque_events');
    final glCount = await count('gl_entries');
    await expectLater(
      PaymentService.reverseReceipt(
        receipt.receiptNumber,
        reason: 'Duplicate retry',
        database: db,
      ),
      throwsStateError,
    );
    expect(await count('cheque_events'), eventCount);
    expect(await count('gl_entries'), glCount);
  });

  test('direct cheque return and cancellation reopen policy collection',
      () async {
    for (final status in const [
      ChequeStatus.returned,
      ChequeStatus.cancelled,
    ]) {
      final suffix = status.name.toUpperCase();
      final policy = await issue('DIRECT-$suffix');
      await InsuranceFinancialService.collectPolicy(
        operationId: 'DIRECT-$suffix-CHEQUE-RECEIPT',
        policyId: policy.policyId,
        date: DateTime(2026, 9, 22),
        database: db,
        instruments: [
          ReceiptInstrumentInput(
            instrumentKey: 'direct-${status.name}-500',
            method: 'cheque',
            amount: 500,
            chequeDraft: {
              'cheque_no': 'DIRECT-$suffix-500',
              'drawer_name': 'Insurance Reversal Customer',
              'bank_name': 'Reversal Bank',
              'issue_date': DateTime(2026, 9, 22).toIso8601String(),
              'due_date': DateTime(2026, 12, 22).toIso8601String(),
            },
          ),
        ],
      );
      final cheque = (await db.query(
        'cheques',
        where: 'cheque_no=?',
        whereArgs: ['DIRECT-$suffix-500'],
        limit: 1,
      ))
          .single;
      final chequeId = (cheque['id'] as num).toInt();
      final reason = 'Direct insurance cheque ${status.name}';

      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: status,
        reason: reason,
        eventDate: DateTime(2026, 9, 23),
      );

      final link = (await db.query(
        'insurance_policy_payments',
        where: 'cheque_id=?',
        whereArgs: [chequeId],
        limit: 1,
      ))
          .single;
      expect(link['status'], 'REVERSED');
      expect(link['reversal_payment_id'], isNull);
      expect(link['reversal_gl_entry_id'], isNotNull);
      expect(link['reversed_at'], isNotNull);
      expect(link['reversal_reason'], reason);
      var balances = await InsuranceFinancialService.balances(
        policy.policyId,
        executor: db,
      );
      expect(balances.customerReceipts, 0);
      expect(balances.customerOutstanding, 2400);

      final eventCount = await count('cheque_events');
      final glCount = await count('gl_entries');
      await ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: status,
        reason: 'Idempotent retry',
        eventDate: DateTime(2026, 9, 23),
      );
      expect(await count('cheque_events'), eventCount);
      expect(await count('gl_entries'), glCount);

      await InsuranceFinancialService.collectPolicy(
        operationId: 'DIRECT-$suffix-REPLACEMENT',
        policyId: policy.policyId,
        date: DateTime(2026, 9, 23),
        database: db,
        instruments: [
          ReceiptInstrumentInput(
            instrumentKey: 'replacement-${status.name}-500',
            method: 'cash',
            amount: 500,
          ),
        ],
      );
      balances = await InsuranceFinancialService.balances(
        policy.policyId,
        executor: db,
      );
      expect(balances.customerReceipts, 500);
      expect(balances.customerOutstanding, 1900);
    }

    expect(await accountBalance('1020'), 0);
    await expectBalancedGl();
  });

  test('insurer voucher reversal restores AP and policy payable once',
      () async {
    final policy = await issue('VOUCHER');
    final voucher =
        await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'REVERSAL-INSURER-PAYMENT',
      policyId: policy.policyId,
      amount: 500,
      date: DateTime(2026, 9, 22),
      method: 'CASH',
      database: db,
    );

    var balances = await InsuranceFinancialService.balances(
      policy.policyId,
      executor: db,
    );
    expect(balances.insurerPayments, 500);
    expect(balances.insurerOutstanding, 1500);
    expect(await accountBalance('1000'), -500);

    await VoucherPaymentService.reverseVoucher(
      voucher.id,
      reason: 'Insurance insurer-payment correction',
      database: db,
    );

    final link = (await db.query('insurance_policy_payments')).single;
    expect(link['status'], 'REVERSED');
    expect(link['reversal_payment_id'], isNull);
    expect(link['reversal_gl_entry_id'], isNotNull);
    expect(link['reversed_at'], isNotNull);
    expect(
      link['reversal_reason'],
      'Insurance insurer-payment correction',
    );
    balances = await InsuranceFinancialService.balances(
      policy.policyId,
      executor: db,
    );
    expect(balances.insurerPayments, 0);
    expect(balances.insurerOutstanding, 2000);
    expect(await accountBalance('1000'), 0);
    expect(
      await accountBalance(
        '2200.S${supplierId.toString().padLeft(4, '0')}',
      ),
      -2000,
    );
    await expectBalancedGl();

    final glCount = await count('gl_entries');
    await expectLater(
      VoucherPaymentService.reverseVoucher(
        voucher.id,
        reason: 'Duplicate retry',
        database: db,
      ),
      throwsStateError,
    );
    expect(await count('gl_entries'), glCount);
    expect(
      await db.query(
        'app_audit_events',
        where: 'action=?',
        whereArgs: ['PAYMENT_VOUCHER_REVERSED'],
      ),
      hasLength(1),
    );
  });

  test('policy cancellation requires linked payments to be reversed first',
      () async {
    final policy = await issue('CANCEL-GUARD');
    final receipt = await InsuranceFinancialService.collectPolicy(
      operationId: 'REVERSAL-CANCEL-GUARD-RECEIPT',
      policyId: policy.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'cash-full',
          method: 'cash',
          amount: 2400,
        ),
      ],
    );

    await expectLater(
      InsuranceFinancialService.cancelPolicy(
        policyId: policy.policyId,
        reason: 'Customer requested cancellation',
      ),
      throwsStateError,
    );
    var stored = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [policy.policyId],
      limit: 1,
    ))
        .single;
    expect(stored['posting_status'], 'POSTED');

    await PaymentService.reverseReceipt(
      receipt.receiptNumber,
      reason: 'Reverse before policy cancellation',
      database: db,
    );
    final reversalGl = await InsuranceFinancialService.cancelPolicy(
      policyId: policy.policyId,
      reason: 'Customer requested cancellation',
    );
    expect(reversalGl, greaterThan(0));
    expect(
      await InsuranceFinancialService.cancelPolicy(
        policyId: policy.policyId,
        reason: 'Idempotent cancellation retry',
      ),
      reversalGl,
    );
    stored = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [policy.policyId],
      limit: 1,
    ))
        .single;
    expect(stored['status'], 'CANCELLED');
    expect(stored['posting_status'], 'REVERSED');
    expect(await accountBalance('1000'), 0);
    expect(await accountBalance('1200.C$clientId'), 0);
    await expectBalancedGl();
  });
}
