import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_policy_cashflow_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late String policyId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_stage6_cashflow_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/stage6.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'insurance-stage6-owner');

    final clientId = await db.insert('clients', {
      'name': 'Stage 6 Customer',
      'type': 'individual',
      'phone': '0599666100',
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
      'name': 'Stage 6 Insurance Company',
      'pid': 'S-STAGE6',
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
      'code': 'STAGE6-INS',
      'name': 'Stage 6 Insurance Company',
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
        operationId: 'STAGE6-POLICY',
        policyNumber: 'STAGE6-POL-001',
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
        createdBy: 'insurance-stage6-owner',
      ),
      database: db,
    );
    policyId = policy.policyId;
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('canonical receipt voucher load and reversals share one cashflow truth',
      () async {
    var snapshot = await InsurancePolicyCashflowService.load(
      policyId,
      executor: db,
    );
    expect(snapshot.balances.sale, 2400);
    expect(snapshot.balances.customerOutstanding, 2400);
    expect(snapshot.balances.insurerOutstanding, 2000);
    expect(snapshot.movements, isEmpty);

    await InsurancePolicyCashflowService.collectCustomer(
      operationId: 'STAGE6-RCPT-CASH',
      policyId: policyId,
      amount: 600,
      date: DateTime(2026, 9, 23),
      method: 'CASH',
      notes: 'cash receipt',
      database: db,
    );
    await InsurancePolicyCashflowService.collectCustomer(
      operationId: 'STAGE6-RCPT-CHEQUE',
      policyId: policyId,
      amount: 400,
      date: DateTime(2026, 9, 24),
      method: 'CHEQUE',
      notes: 'cheque receipt',
      chequeDraft: {
        'cheque_no': 'STAGE6-CHQ-400',
        'drawer_name': 'Stage 6 Customer',
        'bank_name': 'Stage 6 Bank',
        'issue_date': DateTime(2026, 9, 24).toIso8601String(),
        'due_date': DateTime(2026, 10, 24).toIso8601String(),
      },
      database: db,
    );
    await InsurancePolicyCashflowService.payInsurer(
      operationId: 'STAGE6-VOUCHER',
      policyId: policyId,
      amount: 500,
      date: DateTime(2026, 9, 25),
      method: 'CASH',
      notes: 'insurer payment',
      database: db,
    );

    snapshot = await InsurancePolicyCashflowService.load(
      policyId,
      executor: db,
    );
    expect(snapshot.balances.customerReceipts, 1000);
    expect(snapshot.balances.customerOutstanding, 1400);
    expect(snapshot.balances.insurerPayments, 500);
    expect(snapshot.balances.insurerOutstanding, 1500);
    expect(snapshot.movements, hasLength(3));
    expect(
      snapshot.movements.where(
        (movement) => movement.direction == 'CUSTOMER_RECEIPT',
      ),
      hasLength(2),
    );
    expect(
      snapshot.movements
          .singleWhere((movement) => movement.chequeId != null)
          .amount,
      400,
    );

    final cashReceipt = snapshot.movements.singleWhere(
      (movement) =>
          movement.direction == 'CUSTOMER_RECEIPT' && movement.chequeId == null,
    );
    final insurerPayment = snapshot.movements.singleWhere(
      (movement) => movement.direction == 'INSURER_PAYMENT',
    );

    await InsurancePolicyCashflowService.reverseMovement(
      movement: cashReceipt,
      reason: 'Stage 6 receipt correction',
      database: db,
    );
    await InsurancePolicyCashflowService.reverseMovement(
      movement: insurerPayment,
      reason: 'Stage 6 voucher correction',
      database: db,
    );

    snapshot = await InsurancePolicyCashflowService.load(
      policyId,
      executor: db,
    );
    expect(snapshot.balances.customerReceipts, 400);
    expect(snapshot.balances.customerOutstanding, 2000);
    expect(snapshot.balances.insurerPayments, 0);
    expect(snapshot.balances.insurerOutstanding, 2000);
    expect(
      snapshot.movements.where(
        (movement) => movement.status.toUpperCase() == 'REVERSED',
      ),
      hasLength(2),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('cashflow rejects over-collection and insurer over-payment', () async {
    await expectLater(
      InsurancePolicyCashflowService.collectCustomer(
        operationId: 'STAGE6-OVER-RCPT',
        policyId: policyId,
        amount: 2400.01,
        date: DateTime(2026, 9, 23),
        method: 'CASH',
        database: db,
      ),
      throwsStateError,
    );
    await expectLater(
      InsurancePolicyCashflowService.payInsurer(
        operationId: 'STAGE6-OVER-PAY',
        policyId: policyId,
        amount: 2000.01,
        date: DateTime(2026, 9, 23),
        method: 'CASH',
        database: db,
      ),
      throwsStateError,
    );
    expect(await db.query('insurance_policy_payments'), isEmpty);
    expect(await db.query('receipt_headers'), isEmpty);
    expect(await db.query('vouchers'), isEmpty);
  });

  test('load groups multi-instrument receipt by canonical receipt number',
      () async {
    await InsuranceFinancialService.collectPolicy(
      operationId: 'STAGE6-MIXED-RCPT',
      policyId: policyId,
      date: DateTime(2026, 9, 23),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'stage6-mixed-cash',
          method: 'cash',
          amount: 300,
        ),
        ReceiptInstrumentInput(
          instrumentKey: 'stage6-mixed-bank',
          method: 'bank',
          amount: 200,
        ),
      ],
    );

    final snapshot = await InsurancePolicyCashflowService.load(
      policyId,
      executor: db,
    );
    expect(snapshot.movements, hasLength(1));
    final movement = snapshot.movements.single;
    expect(movement.direction, 'CUSTOMER_RECEIPT');
    expect(movement.amount, 500);
    expect(movement.method, 'MIXED');
    expect(movement.receiptNumber, isNotNull);
    expect(snapshot.balances.customerReceipts, 500);
    expect(snapshot.balances.customerOutstanding, 1900);
  });
}
