import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
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

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_policy_stress_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/stress.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'policy-stress-owner');

    company = await InsuranceMasterDataService.createCompany(
      code: 'STRESS-INS',
      name: 'Stress Insurance Company',
      phone: '022200099',
    );
    product = await InsuranceMasterDataService.createProduct(
      companyId: company.id,
      code: 'STRESS-COMP',
      name: 'Stress Comprehensive',
      productType: 'COMPREHENSIVE',
    );
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  PolicyDraft cashDraft({
    required String operationId,
    required String policyNumber,
    required String phone,
    required String plate,
  }) {
    final draft = PolicyDraft()
      ..operationId = operationId
      ..policyNumber = policyNumber
      ..postingDate = DateTime(2026, 9, 23)
      ..vehiclePlate = plate
      ..vehicleMake = 'Toyota'
      ..vehicleModelYear = '2026'
      ..engineCc = '1800'
      ..engineNumber = 'ENG-$operationId'
      ..chassisNumber = 'CHS-$operationId'
      ..insuredName = 'Stress Customer'
      ..insuredPhone = phone
      ..insuranceCompanyId = company.id
      ..companyName = company.name
      ..productId = product.id
      ..coverageType = 'COMPREHENSIVE'
      ..startDate = DateTime(2026, 9, 23)
      ..endDate = DateTime(2027, 9, 22)
      ..buyPrice = 2000
      ..sellPrice = 2400
      ..notes = 'Idempotency stress';
    draft.payment
      ..type = PolicyPaymentPlanType.cashOnly
      ..immediatePaymentMethod = 'CASH'
      ..cashAmount = 2400;
    return draft;
  }

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) n FROM $table');
    return (rows.single['n'] as num).toInt();
  }

  Future<Map<String, int>> financialCounts() async => {
        'policies': await count('insurance_policies'),
        'clients': await count('clients'),
        'vehicles': await count('vehicles'),
        'receipts': await count('receipt_headers'),
        'requests': await count('receipt_requests'),
        'instruments': await count('receipt_instruments'),
        'payments': await count('payments'),
        'policyPayments': await count('insurance_policy_payments'),
        'glEntries': await count('gl_entries'),
        'glLines': await count('gl_lines'),
        'events': await count('insurance_financial_events'),
      };

  Future<void> expectHealthy() async {
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    final totals = (await db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM gl_lines',
    ))
        .single;
    expect(
      (totals['d'] as num).toDouble(),
      closeTo((totals['c'] as num).toDouble(), 0.001),
    );
  }

  test('100 exact retries never duplicate policy receipt payment or GL',
      () async {
    const operationId = 'STRESS-RETRY-100';
    const policyNumber = 'STRESS-POL-100';

    final firstId = await InsurancePolicyService.savePolicyDraft(
      cashDraft(
        operationId: operationId,
        policyNumber: policyNumber,
        phone: '0598777100',
        plate: 'STRESS-100',
      ),
      database: db,
    );
    final stable = await financialCounts();

    for (var index = 0; index < 100; index++) {
      final replayId = await InsurancePolicyService.savePolicyDraft(
        cashDraft(
          operationId: operationId,
          policyNumber: policyNumber,
          phone: '0598777100',
          plate: 'STRESS-100',
        ),
        database: db,
      );
      expect(replayId, firstId, reason: 'retry $index returned another policy');
      expect(
        await financialCounts(),
        stable,
        reason: 'retry $index changed canonical financial row counts',
      );
    }

    expect(stable['policies'], 1);
    expect(stable['clients'], 1);
    expect(stable['vehicles'], 1);
    expect(stable['receipts'], 1);
    expect(stable['requests'], 1);
    expect(stable['instruments'], 1);
    expect(stable['payments'], 1);
    expect(stable['policyPayments'], 1);
    expect(stable['glEntries'], 2);
    await expectHealthy();
  });

  test('10 concurrent exact saves converge to one canonical financial truth',
      () async {
    const operationId = 'STRESS-CONCURRENT-10';
    const policyNumber = 'STRESS-POL-CONCURRENT';

    final ids = await Future.wait(
      List.generate(
        10,
        (_) => InsurancePolicyService.savePolicyDraft(
          cashDraft(
            operationId: operationId,
            policyNumber: policyNumber,
            phone: '0598777200',
            plate: 'STRESS-200',
          ),
          database: db,
        ),
      ),
    );

    expect(ids.toSet(), hasLength(1));
    final counts = await financialCounts();
    expect(counts['policies'], 1);
    expect(counts['clients'], 1);
    expect(counts['vehicles'], 1);
    expect(counts['receipts'], 1);
    expect(counts['requests'], 1);
    expect(counts['instruments'], 1);
    expect(counts['payments'], 1);
    expect(counts['policyPayments'], 1);
    expect(counts['glEntries'], 2);
    await expectHealthy();
  });
}
