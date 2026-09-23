import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/features/insurance_agent/claims/services/insurance_claim_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/home/services/insurance_home_dashboard_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late InsurancePolicyPostingResult policy;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_home_dashboard_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'insurance-home-owner');

    final clientId = await db.insert('clients', {
      'name': 'Home Customer',
      'type': 'individual',
      'phone': '0599777777',
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
    final now = DateTime(2026, 9, 22).toIso8601String();
    await db.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': now,
    });
    final supplierId = await db.insert('suppliers', {
      'name': 'Home Insurance Company',
      'pid': 'S-HOME-INS',
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
      'code': 'HOME-INS',
      'name': 'Home Insurance Company',
      'default_commission_rate': 5.0,
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
    final vehicleId = await db.insert('vehicles', {
      'normalized_number': VehicleTables.normalizeNumber('HOME-001'),
      'number': 'HOME-001',
      'type': 'Kia',
      'model': '2025',
      'client_id': clientId,
      'owner_party_uuid': clientPartyId,
      'is_active': 1,
      'notes': '',
      'created_at': now,
      'updated_at': now,
    });

    policy = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'HOME-POLICY-1',
        policyNumber: 'HOME-POL-001',
        clientId: clientId,
        insuredPartyId: clientPartyId,
        vehicleId: vehicleId,
        vehiclePlate: 'HOME-001',
        companyId: companyId.toString(),
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 10, 10),
        postingDate: DateTime(2026, 9, 22),
        purchasePrice: 2000,
        salePrice: 2400,
        commissionRate: 5,
        createdBy: 'insurance-home-owner',
      ),
      database: db,
    );

    await InsuranceClaimService.createClaim(
      policyId: policy.policyId,
      claimNumber: 'HOME-CLM-001',
      lossDate: DateTime(2026, 9, 20),
      reportedAt: DateTime(2026, 9, 22),
      database: db,
    );
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  test('home dashboard aggregates live insurance operations', () async {
    final snapshot = await InsuranceHomeDashboardService.load(
      asOf: DateTime(2026, 9, 22),
      executor: db,
    );

    expect(snapshot.reporting.postedPolicies, 1);
    expect(snapshot.reporting.activePolicies, 1);
    expect(snapshot.reporting.expiring30, 1);
    expect(snapshot.reporting.openClaims, 1);
    expect(snapshot.reporting.sales, 2400);
    expect(snapshot.policies, hasLength(1));
    expect(snapshot.policies.single.policyId, policy.policyId);
    expect(snapshot.pendingRenewals, hasLength(1));
    expect(snapshot.pendingRenewals.single.policyId, policy.policyId);
    expect(snapshot.openClaims, hasLength(1));
    expect(snapshot.openClaims.single.claimNumber, 'HOME-CLM-001');
    expect(snapshot.companies, hasLength(1));
    expect(snapshot.companies.single.companyName, 'Home Insurance Company');
  });
}
