import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/features/insurance_agent/claims/services/insurance_claim_service.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';

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
    temp = await Directory.systemTemp.createTemp('insurance_claim_');
    YallaStorageService.useRootDirectoryForTesting(
      Directory('${temp.path}/storage'),
    );
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'claims-owner');

    final clientId = await db.insert('clients', {
      'name': 'Claim Customer',
      'type': 'individual',
      'phone': '0599000011',
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
    await db.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': DateTime.now().toIso8601String(),
    });

    final supplierId = await db.insert('suppliers', {
      'name': 'Claims Insurance Company',
      'pid': 'S-CLAIM',
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
    final now = DateTime.now().toIso8601String();
    final companyId = (await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'CLAIM-INS',
      'name': 'Claims Insurance Company',
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
    final vehicleId = await db.insert('vehicles', {
      'normalized_number': 'CLAIM001',
      'number': 'CLAIM-001',
      'type': 'Test Vehicle',
      'model': '2026',
      'client_id': clientId,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });

    final posted = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'CLAIM-POLICY-OP',
        policyNumber: 'CLAIM-POLICY-001',
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId,
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        vehicleId: vehicleId,
        vehiclePlate: 'CLAIM-001',
        vehicleMake: 'Test Vehicle',
        vehicleModelYear: '2026',
        engineCc: '1600',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2027, 1, 1),
        postingDate: DateTime(2026, 1, 1),
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'claims-owner',
      ),
      database: db,
    );
    policyId = posted.policyId;
  });

  tearDown(() async {
    YallaStorageService.useRootDirectoryForTesting(null);
    await session.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
      'creates claim from posted policy with canonical relationships and audit',
      () async {
    final claim = await InsuranceClaimService.createClaim(
      policyId: policyId,
      lossDate: DateTime(2026, 9, 20),
      notes: 'Rear damage',
      workshopRef: 'WO-100',
      actorUserId: 'claims-owner',
      database: db,
    );

    expect(claim.status, 'NEW');
    expect(claim.claimNumber, startsWith('CLM-'));
    expect(claim.insuredPartyId, isNotEmpty);
    expect(claim.vehicleId, greaterThan(0));
    expect(claim.companyId, greaterThan(0));
    expect(
      await InsuranceClaimService.workshopRef(claim.id, executor: db),
      'WO-100',
    );

    final audit = await InsuranceClaimService.timeline(
      claim.id,
      executor: db,
    );
    expect(audit.map((event) => event.action), contains('CLAIM_CREATED'));

    final summary = await InsuranceDashboardService.summary(
      asOf: DateTime(2026, 9, 22),
      executor: db,
    );
    expect(summary.activePolicies, 1);
    expect(summary.openClaims, 1);
    expect(summary.totalSales, 2400);
    expect(summary.totalCost, 2000);
    expect(summary.grossProfit, 400);

    final policies = await InsuranceDashboardService.policies(executor: db);
    expect(policies.single.number, 'CLAIM-POLICY-001');
    expect(policies.single.insuredName, 'Claim Customer');
    final companies =
        await InsuranceDashboardService.companyBalances(executor: db);
    expect(
        companies.any((company) => company.name == 'Claims Insurance Company'),
        isTrue);
  });

  test('enforces state machine and records every valid transition', () async {
    final claim = await InsuranceClaimService.createClaim(
      policyId: policyId,
      database: db,
    );

    await InsuranceClaimService.transitionStatus(
      claimId: claim.id,
      status: 'SUBMITTED',
      database: db,
    );
    await InsuranceClaimService.transitionStatus(
      claimId: claim.id,
      status: 'ASSESSOR',
      database: db,
    );
    await expectLater(
      InsuranceClaimService.transitionStatus(
        claimId: claim.id,
        status: 'CLOSED',
        database: db,
      ),
      throwsStateError,
    );

    final refreshed = (await InsuranceClaimService.listClaims(
      policyId: policyId,
      executor: db,
    ))
        .single;
    expect(refreshed.status, 'ASSESSOR');
    final timeline =
        await InsuranceClaimService.timeline(claim.id, executor: db);
    expect(
      timeline.where((event) => event.action == 'CLAIM_STATUS_CHANGED'),
      hasLength(2),
    );
  });

  test('copies claim attachment to persistent storage and records it',
      () async {
    final claim = await InsuranceClaimService.createClaim(
      policyId: policyId,
      database: db,
    );
    final source = File('${temp.path}/accident-report.pdf');
    await source.writeAsBytes([37, 80, 68, 70, 45, 49, 46, 52]);

    final document = await InsuranceClaimService.attachDocumentFromPath(
      claimId: claim.id,
      documentType: 'ACCIDENT_REPORT',
      sourcePath: source.path,
      database: db,
    );

    expect(document.filePath, startsWith('insurance/'));
    final stored = await YallaStorageService.resolveFile(document.filePath);
    expect(stored, isNotNull);
    expect(await stored!.exists(), isTrue);
    expect(
      await InsuranceClaimService.listDocuments(claim.id, executor: db),
      hasLength(1),
    );
  });

  test('claim links only a canonical repair for the insured vehicle', () async {
    final claim = await InsuranceClaimService.createClaim(
      policyId: policyId,
      database: db,
    );
    final registry = await db.query(
      'sync_entity_registry',
      columns: const ['entity_uuid'],
      where: 'entity_type=? AND local_id=?',
      whereArgs: ['vehicle', claim.vehicleId.toString()],
      limit: 1,
    );
    expect(registry, hasLength(1));
    final vehicleUuid = registry.single['entity_uuid'].toString();

    await db.insert('repairs', {
      'id': 'REPAIR-CLAIM-1',
      'vehicleNumber': 'CLAIM-001',
      'vehicle_entity_uuid': vehicleUuid,
      'beneficiaryName': 'Claim Customer',
      'vehicleStatus': 'received',
      'receivedDate': '2026-09-22T10:00:00Z',
      'is_active': 1,
    });
    await db.insert('repairs', {
      'id': 'REPAIR-OTHER-1',
      'vehicleNumber': 'OTHER-999',
      'vehicle_entity_uuid': 'vehicle-other-uuid',
      'beneficiaryName': 'Other Customer',
      'vehicleStatus': 'received',
      'receivedDate': '2026-09-22T11:00:00Z',
      'is_active': 1,
    });

    final candidates = await InsuranceClaimService.eligibleRepairsForClaim(
        claim.id,
        executor: db);
    expect(candidates.map((row) => row.repairId), ['REPAIR-CLAIM-1']);

    await InsuranceClaimService.linkRepair(
      claimId: claim.id,
      repairId: 'REPAIR-CLAIM-1',
      database: db,
    );
    expect(await InsuranceClaimService.repairId(claim.id, executor: db),
        'REPAIR-CLAIM-1');
    await expectLater(
      InsuranceClaimService.linkRepair(
        claimId: claim.id,
        repairId: 'REPAIR-OTHER-1',
        database: db,
      ),
      throwsStateError,
    );
  });
}
