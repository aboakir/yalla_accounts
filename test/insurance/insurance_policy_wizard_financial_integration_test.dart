import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/services/insurance_policy_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late InsuranceCompanyRecord company;
  late InsuranceProductRecord product;
  late List<String> coverageIds;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_wizard_phase10_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/phase10.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'phase10-owner');

    company = await InsuranceMasterDataService.createCompany(
      code: 'P10-INS',
      name: 'Phase 10 Insurance Company',
      phone: '022200010',
    );
    product = await InsuranceMasterDataService.createProduct(
      companyId: company.id,
      code: 'P10-COMP',
      name: 'Phase 10 Comprehensive',
      productType: 'COMPREHENSIVE',
    );
    coverageIds = [
      await InsuranceMasterDataService.createCoverage(
        productId: product.id,
        code: 'P10-BASIC',
        name: 'Phase 10 Basic Coverage',
      ),
      await InsuranceMasterDataService.createCoverage(
        productId: product.id,
        code: 'P10-EXTRA',
        name: 'Phase 10 Extra Coverage',
      ),
    ];
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  PolicyDraft baseDraft({
    required String operationId,
    required String policyNumber,
    String insuredName = 'Phase 10 Customer',
    String insuredPhone = '0598123456',
    String vehiclePlate = 'P10-10-001',
  }) {
    final draft = PolicyDraft()
      ..operationId = operationId
      ..policyNumber = policyNumber
      ..postingDate = DateTime(2026, 9, 22)
      ..vehiclePlate = vehiclePlate
      ..vehicleMake = 'Toyota'
      ..vehicleModelYear = '2025'
      ..engineCc = '1800'
      ..engineNumber = 'ENG-P10-001'
      ..chassisNumber = 'CHS-P10-001'
      ..insuredName = insuredName
      ..insuredPhone = insuredPhone
      ..insuranceCompanyId = company.id
      ..companyName = company.name
      ..productId = product.id
      ..coverageType = 'COMPREHENSIVE'
      ..startDate = DateTime(2026, 9, 22)
      ..endDate = DateTime(2027, 9, 21)
      ..buyPrice = 2000
      ..sellPrice = 2400
      ..notes = 'Phase 10 wizard integration';
    draft.coverageIds.addAll(coverageIds);
    return draft;
  }

  PolicyDraft installmentDraft({
    required String operationId,
    required String policyNumber,
    String insuredName = 'Phase 10 Customer',
    String insuredPhone = '0598123456',
    String vehiclePlate = 'P10-10-001',
  }) {
    final draft = baseDraft(
      operationId: operationId,
      policyNumber: policyNumber,
      insuredName: insuredName,
      insuredPhone: insuredPhone,
      vehiclePlate: vehiclePlate,
    );
    draft.payment.type = PolicyPaymentPlanType.installmentsNoPromissory;
    draft.payment.installments.addAll([
      PolicyInstallmentItem()
        ..amount = 1200
        ..dueDate = DateTime(2026, 10, 22)
        ..note = 'first installment',
      PolicyInstallmentItem()
        ..amount = 1200
        ..dueDate = DateTime(2026, 11, 22)
        ..note = 'second installment',
    ]);
    return draft;
  }

  Future<int> count(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final rows = await db.query(
      table,
      columns: const ['COUNT(*) AS n'],
      where: where,
      whereArgs: whereArgs,
    );
    return (rows.single['n'] as num).toInt();
  }

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

  Future<double> glTotal(String side) async {
    final row = (await db.rawQuery(
      'SELECT COALESCE(SUM($side),0) n FROM gl_lines',
    ))
        .single;
    return (row['n'] as num).toDouble();
  }

  Future<String> save(PolicyDraft draft) {
    return InsurancePolicyService.savePolicyDraft(draft, database: db);
  }

  test(
      'wizard draft posts canonical policy and dedupes Party customer company and vehicle',
      () async {
    final firstId = await save(installmentDraft(
      operationId: 'P10-CANONICAL-1',
      policyNumber: 'INSURER-P10-001',
    ));

    final first = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [firstId],
      limit: 1,
    ))
        .single;
    expect(first['operation_id'], 'P10-CANONICAL-1');
    expect(first['policy_number'], 'INSURER-P10-001');
    expect(first['document_number'], 'POL-0001');
    expect(first['posting_status'], 'POSTED');
    expect(first['product_id'], product.id);
    expect(first['coverage_type'], 'COMPREHENSIVE');
    expect(
      (jsonDecode(first['coverage_ids_json'].toString()) as List)
          .map((value) => value.toString()),
      unorderedEquals(coverageIds),
    );
    expect(first['engine_number'], 'ENG-P10-001');
    expect(first['chassis_number'], 'CHS-P10-001');
    expect(first['insurance_company_id'].toString(), company.id.toString());
    expect(first['insurer_party_id'], company.partyId);
    expect(
      (first['insurer_supplier_id'] as num).toInt(),
      company.supplierId,
    );

    final clientId = (first['client_id'] as num).toInt();
    final partyId = first['insured_party_id'].toString();
    final vehicleId = (first['vehicle_id'] as num).toInt();
    expect(
      await db.query('clients', where: 'id=?', whereArgs: [clientId]),
      hasLength(1),
    );
    expect(
      await db.query('parties', where: 'id=?', whereArgs: [partyId]),
      hasLength(1),
    );
    final customerRoles = await db.query(
      'party_roles',
      columns: const ['role', 'legacy_id'],
      where: 'party_id=? AND role IN (?,?)',
      whereArgs: [partyId, 'CUSTOMER', 'INSURED'],
    );
    expect(customerRoles.map((row) => row['role']),
        unorderedEquals(['CUSTOMER', 'INSURED']));
    expect(
      customerRoles
          .firstWhere((row) => row['role'] == 'CUSTOMER')['legacy_id']
          .toString(),
      clientId.toString(),
    );

    final vehicle = (await db.query(
      'vehicles',
      where: 'id=?',
      whereArgs: [vehicleId],
      limit: 1,
    ))
        .single;
    expect(vehicle['number'], 'P10-10-001');
    expect(vehicle['normalized_number'], 'P1010001');
    expect((vehicle['client_id'] as num).toInt(), clientId);

    final secondId = await save(installmentDraft(
      operationId: 'P10-CANONICAL-2',
      policyNumber: 'INSURER-P10-002',
    ));
    final second = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [secondId],
      limit: 1,
    ))
        .single;
    expect(secondId, isNot(firstId));
    expect(second['document_number'], 'POL-0002');
    expect(second['client_id'], clientId);
    expect(second['insured_party_id'], partyId);
    expect(second['vehicle_id'], vehicleId);

    expect(
      await count('clients', where: 'phone=?', whereArgs: ['0598123456']),
      1,
    );
    expect(
      await count(
        'parties',
        where: 'display_name=? AND phone=?',
        whereArgs: ['Phase 10 Customer', '0598123456'],
      ),
      1,
    );
    expect(
      await count(
        'vehicles',
        where: 'normalized_number=?',
        whereArgs: ['P1010001'],
      ),
      1,
    );
    expect(
      await count(
        'suppliers',
        where: 'name=?',
        whereArgs: [company.name],
      ),
      1,
    );
    expect(
      await count(
        'insurance_companies',
        where: 'id=? AND party_id=? AND supplier_id=?',
        whereArgs: [company.id, company.partyId, company.supplierId],
      ),
      1,
    );
    expect(
      await count(
        'party_roles',
        where: 'party_id=? AND role=? AND legacy_id=?',
        whereArgs: [
          company.partyId,
          'INSURANCE_COMPANY',
          company.id.toString(),
        ],
      ),
      1,
    );

    expect(
      await count(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['INSURANCE_POLICY'],
      ),
      2,
    );
    expect(await accountBalance('1200.C$clientId'), 4800);
    expect(
      await accountBalance(
        '2200.S${company.supplierId.toString().padLeft(4, '0')}',
      ),
      -4000,
    );
    expect(await glTotal('debit'), closeTo(await glTotal('credit'), 0.001));
  });

  test('wizard CASH payment creates one canonical receipt and clears AR',
      () async {
    final draft = baseDraft(
      operationId: 'P10-CASH-1',
      policyNumber: 'INSURER-P10-CASH',
    );
    draft.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'CASH'
      ..cashAmount = 2400;

    final policyId = await save(draft);
    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [policyId],
      limit: 1,
    ))
        .single;
    final clientId = (policy['client_id'] as num).toInt();

    expect(await count('receipt_headers'), 1);
    expect(await count('receipt_instruments'), 1);
    expect(await count('payments'), 1);
    expect(
      await count(
        'insurance_policy_payments',
        where: 'policy_id=? AND direction=? AND status=?',
        whereArgs: [policyId, 'CUSTOMER_RECEIPT', 'POSTED'],
      ),
      1,
    );
    expect((policy['cash_amount'] as num).toDouble(), 0,
        reason: 'legacy policy cash fields must not be financial truth');
    expect(await accountBalance('1000'), 2400);
    expect(await accountBalance('1010'), 0);
    expect(await accountBalance('1200.C$clientId'), 0);
    expect(await glTotal('debit'), closeTo(await glTotal('credit'), 0.001));
  });

  test('wizard BANK payment creates canonical bank receipt and clears AR',
      () async {
    final draft = baseDraft(
      operationId: 'P10-BANK-1',
      policyNumber: 'INSURER-P10-BANK',
    );
    draft.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'BANK'
      ..cashAmount = 2400;

    final policyId = await save(draft);
    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [policyId],
      limit: 1,
    ))
        .single;
    final clientId = (policy['client_id'] as num).toInt();
    final payment = (await db.query('payments', limit: 1)).single;

    expect(payment['method'].toString().toLowerCase(), 'bank_transfer');
    expect(await count('receipt_headers'), 1);
    expect(await count('insurance_policy_payments'), 1);
    expect(await accountBalance('1000'), 0);
    expect(await accountBalance('1010'), 2400);
    expect(await accountBalance('1200.C$clientId'), 0);
    expect(await glTotal('debit'), closeTo(await glTotal('credit'), 0.001));
  });

  test(
      'wizard cheque creates Receipt plus Cheques Core with issue and due dates only',
      () async {
    final issueDate = DateTime(2026, 9, 22);
    final dueDate = DateTime(2026, 12, 22);
    final draft = baseDraft(
      operationId: 'P10-CHEQUE-1',
      policyNumber: 'INSURER-P10-CHEQUE',
    );
    draft.payment.type = PolicyPaymentPlanType.chequesOnly;
    draft.payment.cheques.add(
      PolicyChequeItem()
        ..issueDate = issueDate
        ..dueDate = dueDate
        ..amount = 2400
        ..bankName = 'Bank of Phase 10'
        ..drawerName = 'Phase 10 Customer'
        ..chequeNumber = 'CHQ-P10-1001',
    );

    final policyId = await save(draft);
    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [policyId],
      limit: 1,
    ))
        .single;
    final clientId = (policy['client_id'] as num).toInt();

    expect(await count('receipt_headers'), 1);
    expect(await count('payments'), 1);
    expect(await count('insurance_policy_payments'), 1);
    expect(await count('cheques'), 1);
    expect(await count('insurance_policy_cheques'), 0,
        reason: 'legacy policy cheque rows must not duplicate Cheques Core');

    final cheque = (await db.query('cheques', limit: 1)).single;
    expect(cheque['cheque_no'], 'CHQ-P10-1001');
    expect(cheque['bank_name'], 'Bank of Phase 10');
    expect((cheque['amount'] as num).toDouble(), 2400);
    expect(DateTime.parse(cheque['issue_date'].toString()), issueDate);
    expect(DateTime.parse(cheque['due_date'].toString()), dueDate);
    expect(cheque['direction'], 'RECEIVED');
    expect(cheque['client_id'], clientId);

    final instrument = (await db.query('receipt_instruments', limit: 1)).single;
    final policyPayment =
        (await db.query('insurance_policy_payments', limit: 1)).single;
    expect(instrument['cheque_id'], cheque['id']);
    expect(policyPayment['cheque_id'], cheque['id']);
    expect(await accountBalance('1020'), 2400);
    expect(await accountBalance('1200.C$clientId'), 0);
    expect(await glTotal('debit'), closeTo(await glTotal('credit'), 0.001));
  });

  test('duplicate physical cheque aborts the whole policy transaction',
      () async {
    final draft = baseDraft(
      operationId: 'P10-CHEQUE-DUPLICATE',
      policyNumber: 'INSURER-P10-CHEQUE-DUPLICATE',
    );
    draft.payment.type = PolicyPaymentPlanType.chequesOnly;
    draft.payment.cheques.addAll([
      PolicyChequeItem()
        ..issueDate = DateTime(2026, 9, 22)
        ..dueDate = DateTime(2026, 12, 22)
        ..amount = 1200
        ..bankName = 'Bank of Phase 10'
        ..drawerName = 'Phase 10 Customer'
        ..chequeNumber = 'CHQ-P10-2001',
      PolicyChequeItem()
        ..issueDate = DateTime(2026, 9, 22)
        ..dueDate = DateTime(2026, 12, 22)
        ..amount = 1200
        ..bankName = 'bank of phase 10'
        ..drawerName = 'Phase 10  Customer'
        ..chequeNumber = 'chq p10 2001',
    ]);

    await expectLater(save(draft), throwsA(isA<StateError>()));
    expect(await count('insurance_policies'), 0);
    expect(await count('receipt_headers'), 0);
    expect(await count('payments'), 0);
    expect(await count('cheques'), 0);
    expect(await count('gl_entries'), 0);
  });

  test('installment and promissory schedules persist without premature GL',
      () async {
    final installmentPolicyId = await save(installmentDraft(
      operationId: 'P10-INSTALLMENTS-1',
      policyNumber: 'INSURER-P10-INSTALLMENTS',
    ));

    final promissory = baseDraft(
      operationId: 'P10-PROMISSORY-1',
      policyNumber: 'INSURER-P10-PROMISSORY',
      vehiclePlate: 'P10-10-002',
    );
    promissory.payment.type = PolicyPaymentPlanType.installmentsWithPromissory;
    promissory.payment.promissories.addAll([
      PolicyPromissoryItem()
        ..amount = 1200
        ..dueDate = DateTime(2026, 10, 22)
        ..imagePath = 'promissory-1.png',
      PolicyPromissoryItem()
        ..amount = 1200
        ..dueDate = DateTime(2026, 11, 22)
        ..imagePath = 'promissory-2.png',
    ]);
    final promissoryPolicyId = await save(promissory);

    final installments = await db.query(
      'insurance_policy_installments',
      where: 'policy_id=?',
      whereArgs: [installmentPolicyId],
      orderBy: 'due_date',
    );
    expect(installments, hasLength(2));
    expect(
      installments.map((row) => (row['amount'] as num).toDouble()),
      [1200, 1200],
    );
    expect(installments.first['note'], 'first installment');

    final promissories = await db.query(
      'insurance_policy_promissories',
      where: 'policy_id=?',
      whereArgs: [promissoryPolicyId],
      orderBy: 'due_date',
    );
    expect(promissories, hasLength(2));
    expect(
      promissories.map((row) => (row['amount'] as num).toDouble()),
      [1200, 1200],
    );

    expect(await count('receipt_headers'), 0);
    expect(await count('receipt_instruments'), 0);
    expect(await count('payments'), 0);
    expect(await count('insurance_policy_payments'), 0);
    expect(
      await count(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['INSURANCE_POLICY'],
      ),
      2,
    );
    expect(
      await count('gl_entries', where: 'source=?', whereArgs: ['PAYMENT']),
      0,
    );
    expect(await accountBalance('1000'), 0);
    expect(await accountBalance('1010'), 0);
    expect(await accountBalance('1020'), 0);
    expect(await glTotal('debit'), closeTo(await glTotal('credit'), 0.001));
  });

  test('wizard retry is idempotent and changed retry is rejected', () async {
    final draft = baseDraft(
      operationId: 'P10-RETRY-1',
      policyNumber: 'INSURER-P10-RETRY',
    );
    draft.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'CASH'
      ..cashAmount = 2400;

    final firstId = await save(draft);
    final retryId = await save(draft);
    expect(retryId, firstId);
    expect(await count('insurance_policies'), 1);
    expect(await count('receipt_headers'), 1);
    expect(await count('payments'), 1);
    expect(await count('insurance_policy_payments'), 1);
    expect(await count('gl_entries'), 2);
    expect(
      await count('clients', where: 'phone=?', whereArgs: ['0598123456']),
      1,
    );
    expect(
      await count(
        'vehicles',
        where: 'normalized_number=?',
        whereArgs: ['P1010001'],
      ),
      1,
    );

    final changed = baseDraft(
      operationId: 'P10-RETRY-1',
      policyNumber: 'INSURER-P10-RETRY',
    )..sellPrice = 2500;
    changed.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'CASH'
      ..cashAmount = 2500;

    await expectLater(save(changed), throwsA(isA<StateError>()));
    expect(await count('insurance_policies'), 1);
    expect(await count('receipt_headers'), 1);
    expect(await count('payments'), 1);
    expect(await count('gl_entries'), 2);

    final changedVehicle = baseDraft(
      operationId: 'P10-RETRY-1',
      policyNumber: 'INSURER-P10-RETRY',
    )
      ..vehicleMake = 'Honda'
      ..vehicleModelYear = '2030';
    changedVehicle.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'CASH'
      ..cashAmount = 2400;

    await expectLater(save(changedVehicle), throwsA(isA<StateError>()));
    final canonicalVehicle = (await db.query(
      'vehicles',
      columns: const ['type', 'model'],
      where: 'normalized_number=?',
      whereArgs: const ['P1010001'],
      limit: 1,
    ))
        .single;
    expect(canonicalVehicle['type'], 'Toyota');
    expect(canonicalVehicle['model'], '2025');
    expect(await count('insurance_policies'), 1);
    expect(await count('receipt_headers'), 1);
    expect(await count('gl_entries'), 2);
  });

  test('wizard retry reconstructed after commit reuses canonical posting date',
      () async {
    final first = baseDraft(
      operationId: 'P10-RETRY-REBUILT',
      policyNumber: 'INSURER-P10-RETRY-REBUILT',
    )..postingDate = DateTime(2026, 9, 18);
    first.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'CASH'
      ..cashAmount = 2400;

    final firstId = await save(first);
    final rebuilt = baseDraft(
      operationId: 'P10-RETRY-REBUILT',
      policyNumber: 'INSURER-P10-RETRY-REBUILT',
    )..postingDate = null;
    rebuilt.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'CASH'
      ..cashAmount = 2400;

    expect(await save(rebuilt), firstId);
    expect(rebuilt.postingDate, DateTime(2026, 9, 18));
    expect(await count('insurance_policies'), 1);
    expect(await count('receipt_headers'), 1);
    expect(await count('payments'), 1);
    expect(await count('gl_entries'), 2);
  });

  test('supplied policy document advances the canonical sequence', () async {
    final supplied = installmentDraft(
      operationId: 'P10-DOCUMENT-SUPPLIED',
      policyNumber: 'INSURER-P10-DOC-100',
    )..documentNumber = 'POL-0100';
    await save(supplied);
    expect(supplied.documentNumber, 'POL-0100');

    final automatic = installmentDraft(
      operationId: 'P10-DOCUMENT-AUTO',
      policyNumber: 'INSURER-P10-DOC-101',
      vehiclePlate: 'P10-DOCUMENT-2',
    );
    await save(automatic);
    expect(automatic.documentNumber, 'POL-0101');
    expect(await count('insurance_policies'), 2);
  });

  test(
      'late issuance failure rolls back policy identities schedules GL and number',
      () async {
    final sequenceBefore = (await db.query(
      'document_sequences',
      columns: const ['next_value'],
      where: 'document_type=?',
      whereArgs: ['INSURANCE_POLICY'],
      limit: 1,
    ))
        .single['next_value'];
    await db.execute('''
      CREATE TRIGGER phase10_reject_policy_event
      BEFORE INSERT ON insurance_financial_events
      WHEN NEW.event_type='POLICY_ISSUED'
      BEGIN SELECT RAISE(ABORT,'forced Phase 10 late failure'); END
    ''');

    await expectLater(
      save(installmentDraft(
        operationId: 'P10-ROLLBACK-1',
        policyNumber: 'INSURER-P10-ROLLBACK',
        insuredPhone: '0598999999',
        vehiclePlate: 'P10-ROLLBACK',
      )),
      throwsA(anything),
    );

    expect(
      await count(
        'insurance_policies',
        where: 'operation_id=?',
        whereArgs: ['P10-ROLLBACK-1'],
      ),
      0,
    );
    expect(
      await count('clients', where: 'phone=?', whereArgs: ['0598999999']),
      0,
    );
    expect(
      await count(
        'vehicles',
        where: 'normalized_number=?',
        whereArgs: ['P10ROLLBACK'],
      ),
      0,
    );
    expect(await count('insurance_policy_installments'), 0);
    expect(await count('insurance_financial_events'), 0);
    expect(
      await count(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['INSURANCE_POLICY'],
      ),
      0,
    );
    expect(await count('receipt_headers'), 0);
    final sequenceAfter = (await db.query(
      'document_sequences',
      columns: const ['next_value'],
      where: 'document_type=?',
      whereArgs: ['INSURANCE_POLICY'],
      limit: 1,
    ))
        .single['next_value'];
    expect(sequenceAfter, sequenceBefore);
  });

  test('late receipt failure rolls issuance and receipt back as one unit',
      () async {
    final sequenceBefore = (await db.query(
      'document_sequences',
      columns: const ['next_value'],
      where: 'document_type=?',
      whereArgs: ['INSURANCE_POLICY'],
      limit: 1,
    ))
        .single['next_value'];
    await db.execute('''
      CREATE TRIGGER phase10_reject_receipt_request
      BEFORE INSERT ON receipt_requests
      BEGIN SELECT RAISE(ABORT,'forced Phase 10 receipt failure'); END
    ''');

    final draft = baseDraft(
      operationId: 'P10-RECEIPT-ROLLBACK',
      policyNumber: 'INSURER-P10-RECEIPT-ROLLBACK',
      insuredPhone: '0598666666',
      vehiclePlate: 'P10-RECEIPT-ROLLBACK',
    );
    draft.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'CASH'
      ..cashAmount = 2400;

    await expectLater(save(draft), throwsA(anything));

    expect(
      await count(
        'insurance_policies',
        where: 'operation_id=?',
        whereArgs: ['P10-RECEIPT-ROLLBACK'],
      ),
      0,
    );
    expect(
      await count('clients', where: 'phone=?', whereArgs: ['0598666666']),
      0,
    );
    expect(await count('receipt_headers'), 0);
    expect(await count('receipt_instruments'), 0);
    expect(await count('receipt_requests'), 0);
    expect(await count('payments'), 0);
    expect(await count('insurance_policy_payments'), 0);
    expect(await count('insurance_financial_events'), 0);
    expect(await count('gl_entries'), 0);
    final sequenceAfter = (await db.query(
      'document_sequences',
      columns: const ['next_value'],
      where: 'document_type=?',
      whereArgs: ['INSURANCE_POLICY'],
      limit: 1,
    ))
        .single['next_value'];
    expect(sequenceAfter, sequenceBefore);
  });

  test('insurer policy number is unique across operations', () async {
    await save(installmentDraft(
      operationId: 'P10-UNIQUE-1',
      policyNumber: 'INSURER-P10-UNIQUE',
    ));
    await expectLater(
      save(installmentDraft(
        operationId: 'P10-UNIQUE-2',
        policyNumber: 'INSURER-P10-UNIQUE',
        insuredName: 'Another Customer',
        insuredPhone: '0598777777',
        vehiclePlate: 'P10-UNIQUE-2',
      )),
      throwsA(anything),
    );

    expect(
      await count(
        'insurance_policies',
        where: 'policy_number=?',
        whereArgs: ['INSURER-P10-UNIQUE'],
      ),
      1,
    );
    expect(
      await count(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['INSURANCE_POLICY'],
      ),
      1,
    );
    expect(
      await count('clients', where: 'phone=?', whereArgs: ['0598777777']),
      0,
      reason:
          'the rejected duplicate operation must roll back new identity rows',
    );
  });

  test('canonical collection prevents policy overpayment atomically', () async {
    final policyId = await save(installmentDraft(
      operationId: 'P10-OVERPAY-POLICY',
      policyNumber: 'INSURER-P10-OVERPAY',
    ));
    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [policyId],
      limit: 1,
    ))
        .single;
    final clientId = (policy['client_id'] as num).toInt();

    await InsuranceFinancialService.collectPolicy(
      operationId: 'P10-OVERPAY-FIRST',
      policyId: policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'cash-1000',
          method: 'CASH',
          amount: 1000,
        ),
      ],
    );

    await expectLater(
      InsuranceFinancialService.collectPolicy(
        operationId: 'P10-OVERPAY-REJECTED',
        policyId: policyId,
        date: DateTime(2026, 9, 22),
        database: db,
        instruments: const [
          ReceiptInstrumentInput(
            instrumentKey: 'cash-1400-01',
            method: 'CASH',
            amount: 1400.01,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    expect(await count('receipt_headers'), 1);
    expect(await count('payments'), 1);
    expect(await count('insurance_policy_payments'), 1);
    expect(await accountBalance('1000'), 1000);
    expect(await accountBalance('1200.C$clientId'), 1400);
    final balances = await InsuranceFinancialService.balances(
      policyId,
      executor: db,
    );
    expect(balances.customerReceipts, 1000);
    expect(balances.customerOutstanding, 1400);
    expect(await glTotal('debit'), closeTo(await glTotal('credit'), 0.001));
  });
}
