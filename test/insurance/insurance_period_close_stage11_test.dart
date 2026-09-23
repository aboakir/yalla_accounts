import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_endorsement_refund_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_period_close_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_settlement_service.dart';

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
    temp = await Directory.systemTemp.createTemp('insurance_stage11_close_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/stage11.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'insurance-stage11-owner');

    clientId = await db.insert('clients', {
      'name': 'Stage 11 Customer',
      'type': 'individual',
      'phone': '0599111100',
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
    final now = DateTime(2026, 9, 1).toIso8601String();
    await db.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': now,
    });

    supplierId = await db.insert('suppliers', {
      'name': 'Stage 11 Insurance Company',
      'pid': 'S-STAGE11',
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
    companyId = (await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'STAGE11-INS',
      'name': 'Stage 11 Insurance Company',
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
  Future<InsurancePolicyPostingResult> issue({
    required String operationId,
    required String policyNumber,
    DateTime? postingDate,
  }) async {
    final date = postingDate ?? DateTime(2026, 9, 10);
    return InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: operationId,
        policyNumber: policyNumber,
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId,
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2027, 8, 31),
        postingDate: date,
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'insurance-stage11-owner',
      ),
      database: db,
    );
  }

  test('pending settlement blocks close then paid settlement closes cleanly',
      () async {
    final policy = await issue(
      operationId: 'STAGE11-POLICY',
      policyNumber: 'STAGE11-POL-001',
    );

    await InsuranceFinancialService.collectPolicy(
      operationId: 'STAGE11-PRE-CLOSE-CHEQUE',
      policyId: policy.policyId,
      date: DateTime(2026, 9, 15),
      database: db,
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: 'stage11-cheque-100',
          method: 'cheque',
          amount: 100,
          chequeDraft: {
            'cheque_no': 'STAGE11-CHQ-100',
            'drawer_name': 'Stage 11 Customer',
            'bank_name': 'Stage 11 Bank',
            'issue_date': DateTime(2026, 9, 15).toIso8601String(),
            'due_date': DateTime(2026, 10, 15).toIso8601String(),
          },
        ),
      ],
    );
    final chequeId =
        ((await db.query('cheques', limit: 1)).single['id'] as num).toInt();

    final settlement = await InsuranceSettlementService.buildSettlement(
      operationId: 'STAGE11-SET',
      companyId: int.parse(companyId),
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      database: db,
    );
    var reconciliation = await InsurancePeriodCloseService.reconcile(
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      executor: db,
    );
    expect(reconciliation.pendingSettlements, 1);
    expect(reconciliation.isClean, isFalse);
    await expectLater(
      InsurancePeriodCloseService.closePeriod(
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        closedBy: 'stage11-test',
        database: db,
      ),
      throwsStateError,
    );

    await InsuranceSettlementService.postSettlement(
      settlement.id,
      database: db,
    );
    await InsuranceSettlementService.paySettlement(
      operationId: 'STAGE11-SET-PAY',
      settlementId: settlement.id,
      amount: settlement.payable,
      date: DateTime(2026, 9, 25),
      method: 'CASH',
      database: db,
    );

    reconciliation = await InsurancePeriodCloseService.reconcile(
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      executor: db,
    );
    expect(reconciliation.isClean, isTrue);
    expect(reconciliation.glDebit, reconciliation.glCredit);
    expect(reconciliation.foreignKeyViolations, 0);

    final closed = await InsurancePeriodCloseService.closePeriod(
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      closedBy: 'stage11-test',
      database: db,
    );
    expect(closed.status, 'CLOSED');
    expect(closed.reconciliation.isClean, isTrue);
    final retry = await InsurancePeriodCloseService.closePeriod(
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      closedBy: 'stage11-test',
      database: db,
    );
    expect(retry.id, closed.id);
    expect(
      await db.query('insurance_period_closes',
          where: 'status=?', whereArgs: ['CLOSED']),
      hasLength(1),
    );

    await expectLater(
      ChequeAccountingService.transitionStatus(
        chequeId: chequeId,
        newStatus: ChequeStatus.returned,
        reason: 'Backdated closed-period return',
        eventDate: DateTime(2026, 9, 20),
      ),
      throwsStateError,
    );
    final stillReceived = (await db.query(
      'cheques',
      columns: const ['status'],
      where: 'id=?',
      whereArgs: [chequeId],
    ))
        .single;
    expect(stillReceived['status'], ChequeStatus.received.name);

    final returned = await ChequeAccountingService.transitionStatus(
      chequeId: chequeId,
      newStatus: ChequeStatus.returned,
      reason: 'October return',
      eventDate: DateTime(2026, 10, 1),
    );
    expect(returned.status, ChequeStatus.returned);

    await expectLater(
      InsuranceFinancialService.collectPolicy(
        operationId: 'STAGE11-CLOSED-RCPT',
        policyId: policy.policyId,
        date: DateTime(2026, 9, 20),
        database: db,
        instruments: const [
          ReceiptInstrumentInput(
            instrumentKey: 'closed-cash',
            method: 'cash',
            amount: 100,
          ),
        ],
      ),
      throwsStateError,
    );
    await expectLater(
      InsuranceFinancialService.payInsuranceCompanyForPolicy(
        operationId: 'STAGE11-CLOSED-PAY',
        policyId: policy.policyId,
        amount: 100,
        date: DateTime(2026, 9, 20),
        method: 'CASH',
        database: db,
      ),
      throwsStateError,
    );
    await expectLater(
      InsuranceEndorsementRefundService.postEndorsement(
        operationId: 'STAGE11-CLOSED-END',
        policyId: policy.policyId,
        endorsementType: 'ADD_COVERAGE',
        effectiveDate: DateTime(2026, 9, 20),
        deltaSale: 100,
        deltaCost: 80,
        database: db,
      ),
      throwsStateError,
    );
    await expectLater(
      InsuranceEndorsementRefundService.refundCustomer(
        operationId: 'STAGE11-CLOSED-REFUND',
        policyId: policy.policyId,
        amount: 10,
        date: DateTime(2026, 9, 20),
        method: 'CASH',
        database: db,
      ),
      throwsStateError,
    );
    await expectLater(
      issue(
        operationId: 'STAGE11-CLOSED-POLICY',
        policyNumber: 'STAGE11-CLOSED-002',
        postingDate: DateTime(2026, 9, 20),
      ),
      throwsStateError,
    );
    await expectLater(
      InsuranceSettlementService.paySettlement(
        operationId: 'STAGE11-CLOSED-SET-PAY',
        settlementId: settlement.id,
        amount: 1,
        date: DateTime(2026, 9, 20),
        method: 'CASH',
        database: db,
      ),
      throwsStateError,
    );
  });

  test('broken canonical payment link prevents period close', () async {
    final policy = await issue(
      operationId: 'STAGE11-BROKEN-POLICY',
      policyNumber: 'STAGE11-BROKEN-001',
    );
    await db.insert('insurance_policy_payments', {
      'id': 'STAGE11-BROKEN-LINK',
      'policy_id': policy.policyId,
      'direction': 'CUSTOMER_RECEIPT',
      'receipt_number': 999999,
      'payment_id': 'missing-payment',
      'amount': 10.0,
      'currency': 'ILS',
      'status': 'POSTED',
      'created_at': DateTime(2026, 9, 15).toIso8601String(),
    });

    final reconciliation = await InsurancePeriodCloseService.reconcile(
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      executor: db,
    );
    expect(reconciliation.malformedPayments, 1);
    expect(reconciliation.isClean, isFalse);
    await expectLater(
      InsurancePeriodCloseService.closePeriod(
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        closedBy: 'stage11-test',
        database: db,
      ),
      throwsStateError,
    );
    expect(await db.query('insurance_period_closes'), isEmpty);
  });
}
