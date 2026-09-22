import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/services/insurance_endorsement_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/services/insurance_policy_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late InsuranceCompanyRecord company;
  late InsuranceProductRecord product;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_endorsement_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/endorsement.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'endorsement-owner');

    company = await InsuranceMasterDataService.createCompany(
      code: 'END-INS',
      name: 'Endorsement Insurance Company',
      phone: '022233344',
    );
    product = await InsuranceMasterDataService.createProduct(
      companyId: company.id,
      code: 'END-COMP',
      name: 'Endorsement Comprehensive',
      productType: 'COMPREHENSIVE',
    );
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  PolicyDraft draft(String operationId, String policyNumber) {
    final value = PolicyDraft()
      ..operationId = operationId
      ..policyNumber = policyNumber
      ..postingDate = DateTime(2026, 9, 22)
      ..vehiclePlate = 'END-10-001'
      ..vehicleMake = 'Toyota'
      ..vehicleModelYear = '2025'
      ..engineCc = '1800'
      ..engineNumber = 'END-ENG-1'
      ..chassisNumber = 'END-CHS-1'
      ..insuredName = 'Endorsement Customer'
      ..insuredPhone = '0598111222'
      ..insuranceCompanyId = company.id
      ..companyName = company.name
      ..productId = product.id
      ..coverageType = 'COMPREHENSIVE'
      ..startDate = DateTime(2026, 9, 22)
      ..endDate = DateTime(2027, 9, 21)
      ..buyPrice = 2000
      ..sellPrice = 2400
      ..notes = 'endorsement integrity baseline';
    value.payment.type = PolicyPaymentPlanType.installmentsNoPromissory;
    value.payment.installments.addAll([
      PolicyInstallmentItem()
        ..amount = 1200
        ..dueDate = DateTime(2026, 10, 22),
      PolicyInstallmentItem()
        ..amount = 1200
        ..dueDate = DateTime(2026, 11, 22),
    ]);
    return value;
  }

  Future<Map<String, Object?>> policy(String id) async {
    return (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    ))
        .single;
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

  test('posting endorsement updates policy AR AP GL version and is idempotent',
      () async {
    final policyId = await InsurancePolicyService.savePolicyDraft(
      draft('END-BASE-1', 'INS-END-001'),
      database: db,
    );
    final before = await policy(policyId);
    final clientId = (before['client_id'] as num).toInt();
    final supplierId = (before['insurer_supplier_id'] as num).toInt();

    final debitBefore = await glTotal('debit');
    final creditBefore = await glTotal('credit');
    final command = InsuranceEndorsementCommand(
      operationId: 'END-OP-1',
      policyId: policyId,
      endorsementType: 'COVERAGE_CHANGE',
      effectiveDate: DateTime(2026, 10, 1),
      deltaSale: 230,
      deltaCost: 180,
      deltaTax: 30,
      payload: const {'note': 'add coverage'},
      createdBy: 'endorsement-owner',
    );

    final posted = await InsuranceEndorsementService.postEndorsement(
      command,
      database: db,
    );
    final after = await policy(policyId);

    expect(posted.wasExisting, isFalse);
    expect(posted.status, 'POSTED');
    expect(posted.versionNo, 2);
    expect(posted.glEntryId, isNotNull);
    expect((after['net_sale_amount'] as num).toDouble(), 2630);
    expect((after['net_insurer_payable'] as num).toDouble(), 2180);
    expect((after['sell_price'] as num).toDouble(), 2600);
    expect((after['buy_price'] as num).toDouble(), 2180);
    expect((after['tax'] as num).toDouble(), 30);
    expect((after['gross_profit'] as num).toDouble(), 450);

    expect(await accountBalance('1200.C$clientId'), 2630);
    expect(
      await accountBalance('2200.S${supplierId.toString().padLeft(4, '0')}'),
      -2180,
    );
    expect(await glTotal('debit'), closeTo(debitBefore + 410, 0.001));
    expect(await glTotal('credit'), closeTo(creditBefore + 410, 0.001));
    final retry = await InsuranceEndorsementService.postEndorsement(
      command,
      database: db,
    );
    expect(retry.wasExisting, isTrue);
    expect(retry.endorsementId, posted.endorsementId);
    expect(
      await db.query(
        'insurance_endorsements',
        where: 'policy_id=?',
        whereArgs: [policyId],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'insurance_policy_versions',
        where: 'policy_id=?',
        whereArgs: [policyId],
      ),
      hasLength(2),
    );

    await expectLater(
      InsuranceEndorsementService.postEndorsement(
        InsuranceEndorsementCommand(
          operationId: 'END-OP-1',
          policyId: policyId,
          endorsementType: 'COVERAGE_CHANGE',
          effectiveDate: DateTime(2026, 10, 1),
          deltaSale: 231,
          deltaCost: 180,
          deltaTax: 30,
        ),
        database: db,
      ),
      throwsStateError,
    );
  });

  test('reversal restores exact policy balances and then permits cancellation',
      () async {
    final policyId = await InsurancePolicyService.savePolicyDraft(
      draft('END-BASE-2', 'INS-END-002'),
      database: db,
    );
    final posted = await InsuranceEndorsementService.postEndorsement(
      InsuranceEndorsementCommand(
        operationId: 'END-OP-2',
        policyId: policyId,
        endorsementType: 'PREMIUM_ADJUSTMENT',
        effectiveDate: DateTime(2026, 10, 5),
        deltaSale: 230,
        deltaCost: 180,
        deltaTax: 30,
        createdBy: 'endorsement-owner',
      ),
      database: db,
    );

    await expectLater(
      InsuranceFinancialService.cancelPolicy(
        policyId: policyId,
        reason: 'must reverse endorsement first',
        createdBy: 'endorsement-owner',
        database: db,
      ),
      throwsStateError,
    );

    final reversal = await InsuranceEndorsementService.reverseEndorsement(
      endorsementId: posted.endorsementId,
      reversalDate: DateTime(2026, 10, 6),
      reason: 'customer request',
      createdBy: 'endorsement-owner',
      database: db,
    );
    final restored = await policy(policyId);
    expect(reversal.status, 'REVERSED');
    expect(reversal.versionNo, 3);
    expect(reversal.reversalGlEntryId, isNotNull);
    expect((restored['net_sale_amount'] as num).toDouble(), 2400);
    expect((restored['net_insurer_payable'] as num).toDouble(), 2000);
    expect((restored['sell_price'] as num).toDouble(), 2400);
    expect((restored['buy_price'] as num).toDouble(), 2000);
    expect((restored['tax'] as num).toDouble(), 0);
    expect((restored['gross_profit'] as num).toDouble(), 400);

    final retry = await InsuranceEndorsementService.reverseEndorsement(
      endorsementId: posted.endorsementId,
      reversalDate: DateTime(2026, 10, 6),
      reason: 'customer request',
      createdBy: 'endorsement-owner',
      database: db,
    );
    expect(retry.wasExisting, isTrue);
    expect(retry.status, 'REVERSED');

    final policyReversal = await InsuranceFinancialService.cancelPolicy(
      policyId: policyId,
      reason: 'customer cancelled after endorsement reversal',
      createdBy: 'endorsement-owner',
      database: db,
    );
    expect(policyReversal, isPositive);
    final cancelled = await policy(policyId);
    expect(cancelled['status'], 'CANCELLED');
    expect(cancelled['posting_status'], 'REVERSED');
  });
}
