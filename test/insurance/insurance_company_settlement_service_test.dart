import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_company_settlement_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/services/insurance_endorsement_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int clientId;
  late String clientPartyId;
  late int supplierId;
  late String supplierPartyId;
  late int companyId;
  late int vehicleId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_settlement_');
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    session = await startAccountingSession(db, 'insurance-owner');

    clientId = await db.insert('clients', {
      'name': 'Settlement Customer',
      'type': 'individual',
      'phone': '0599555000',
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

    supplierId = await db.insert('suppliers', {'name': 'Settlement Insurance'});
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
    companyId = await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'SETTLE-INS',
      'name': 'Settlement Insurance',
      'default_commission_rate': 10.0,
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

    vehicleId = await db.insert('vehicles', {
      'normalized_number': VehicleTables.normalizeNumber('SET-001'),
      'number': 'SET-001',
      'type': 'Toyota',
      'model': '2025',
      'client_id': clientId,
      'owner_party_uuid': clientPartyId,
      'is_active': 1,
      'notes': '',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<InsurancePolicyPostingResult> issue(String operation, String number) {
    return InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: operation,
        policyNumber: number,
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId.toString(),
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        vehicleId: vehicleId,
        vehiclePlate: 'SET-001',
        startDate: DateTime(2026, 9, 23),
        endDate: DateTime(2027, 9, 22),
        postingDate: DateTime(2026, 9, 23),
        purchasePrice: 2000,
        salePrice: 2400,
        basePremium: 2000,
        commissionRate: 10,
        createdBy: 'insurance-owner',
      ),
      database: db,
    );
  }

  final monthStart = DateTime(2026, 9, 1);
  final monthEnd = DateTime(2026, 9, 30);

  test(
      'settlement preview reconciles policy liability and direct insurer payment',
      () async {
    final posted = await issue('SET-POL-1', 'SET-POL-001');
    await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'SET-DIRECT-PAY-1',
      policyId: posted.policyId,
      amount: 300,
      date: DateTime(2026, 9, 23),
      method: 'cash',
      database: db,
    );

    final preview = await InsuranceCompanySettlementService.preview(
      companyId: companyId,
      periodStart: monthStart,
      periodEnd: monthEnd,
      executor: db,
    );
    expect(preview.grossPolicies, 2000);
    expect(preview.cancellations, 0);
    expect(preview.commission, 200);
    expect(preview.previousPayments, 300);
    expect(preview.payable, 1700);
    expect(preview.settlementPayments, 0);
    expect(preview.outstanding, 1700);
    expect(preview.itemsOf('POLICY_ISSUE'), hasLength(1));
    expect(preview.itemsOf('POLICY_PAYMENT'), hasLength(1));
  });

  test(
      'draft posts once and canonical settlement payments close it without overpay',
      () async {
    await issue('SET-POL-2', 'SET-POL-002');
    final draft = await InsuranceCompanySettlementService.saveDraft(
      companyId: companyId,
      periodStart: monthStart,
      periodEnd: monthEnd,
      database: db,
    );
    expect(draft.status, 'DRAFT');
    expect(draft.payable, 2000);

    final posted = await InsuranceCompanySettlementService.postDraft(
      draft.settlementId!,
      database: db,
    );
    expect(posted.status, 'POSTED');

    await InsuranceCompanySettlementService.paySettlement(
      operationId: 'SET-PAY-1',
      settlementId: draft.settlementId!,
      amount: 700,
      date: DateTime(2026, 9, 23),
      method: 'cash',
      database: db,
    );
    var current = await InsuranceCompanySettlementService.load(
      draft.settlementId!,
      executor: db,
    );
    expect(current.status, 'PARTIAL');
    expect(current.settlementPayments, 700);
    expect(current.outstanding, 1300);

    await expectLater(
      InsuranceCompanySettlementService.paySettlement(
        operationId: 'SET-PAY-OVER',
        settlementId: draft.settlementId!,
        amount: 1400,
        date: DateTime(2026, 9, 23),
        method: 'cash',
        database: db,
      ),
      throwsStateError,
    );

    await InsuranceCompanySettlementService.paySettlement(
      operationId: 'SET-PAY-2',
      settlementId: draft.settlementId!,
      amount: 1300,
      date: DateTime(2026, 9, 23),
      method: 'cash',
      database: db,
    );
    current = await InsuranceCompanySettlementService.load(
      draft.settlementId!,
      executor: db,
    );
    expect(current.status, 'PAID');
    expect(current.outstanding, 0);

    await InsuranceCompanySettlementService.paySettlement(
      operationId: 'SET-PAY-2',
      settlementId: draft.settlementId!,
      amount: 1300,
      date: DateTime(2026, 9, 23),
      method: 'cash',
      database: db,
    );
    current = await InsuranceCompanySettlementService.load(
      draft.settlementId!,
      executor: db,
    );
    expect(current.settlementPayments, 2000);
    expect(
      await db.query(
        'insurance_policy_payments',
        where: 'settlement_id=? AND status=?',
        whereArgs: [draft.settlementId!, 'POSTED'],
      ),
      hasLength(2),
    );
  });

  test('endorsement and reversal appear as separate period liability movements',
      () async {
    final posted = await issue('SET-POL-3', 'SET-POL-003');
    final endorsement = await InsuranceEndorsementService.postEndorsement(
      InsuranceEndorsementCommand(
        operationId: 'SET-END-1',
        policyId: posted.policyId,
        endorsementType: 'ADD_COVERAGE',
        effectiveDate: DateTime(2026, 9, 23),
        deltaSale: 250,
        deltaCost: 200,
        createdBy: 'insurance-owner',
      ),
      database: db,
    );
    await InsuranceEndorsementService.reverseEndorsement(
      endorsementId: endorsement.endorsementId,
      reversalDate: DateTime(2026, 9, 23),
      reason: 'Settlement reversal test',
      createdBy: 'insurance-owner',
      database: db,
    );

    final preview = await InsuranceCompanySettlementService.preview(
      companyId: companyId,
      periodStart: monthStart,
      periodEnd: monthEnd,
      executor: db,
    );
    expect(preview.grossPolicies, 2200);
    expect(preview.cancellations, 200);
    expect(preview.payable, 2000);
    expect(preview.itemsOf('ENDORSEMENT'), hasLength(1));
    expect(preview.itemsOf('ENDORSEMENT_REVERSAL'), hasLength(1));
  });

  test('same source event cannot be claimed by overlapping settlements',
      () async {
    await issue('SET-POL-4', 'SET-POL-004');
    final first = await InsuranceCompanySettlementService.saveDraft(
      companyId: companyId,
      periodStart: DateTime(2026, 9, 20),
      periodEnd: DateTime(2026, 9, 25),
      database: db,
    );
    expect(first.itemsOf('POLICY_ISSUE'), hasLength(1));

    await expectLater(
      InsuranceCompanySettlementService.saveDraft(
        companyId: companyId,
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        database: db,
      ),
      throwsStateError,
    );
  });
}
