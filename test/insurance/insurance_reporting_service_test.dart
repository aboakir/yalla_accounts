import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/claims/services/insurance_claim_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/reports/services/insurance_reporting_service.dart';

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
  late InsurancePolicyPostingResult policy;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_reporting_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'insurance-report-owner');

    clientId = await db.insert('clients', {
      'name': 'Reporting Customer',
      'type': 'individual',
      'phone': '0599777777',
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
      'name': 'Reporting Insurance Company',
      'pid': 'S-REPORT-INS',
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
    companyId = await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'REPORT-INS',
      'name': 'Reporting Insurance Company',
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

    vehicleId = await db.insert('vehicles', {
      'normalized_number': VehicleTables.normalizeNumber('REPORT-001'),
      'number': 'REPORT-001',
      'type': 'Toyota',
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
        operationId: 'REPORT-POLICY-1',
        policyNumber: 'REPORT-POL-001',
        clientId: clientId,
        insuredPartyId: clientPartyId,
        vehicleId: vehicleId,
        vehiclePlate: 'REPORT-001',
        companyId: companyId.toString(),
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 10, 10),
        postingDate: DateTime(2026, 9, 1),
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'insurance-report-owner',
      ),
      database: db,
    );

    await InsuranceFinancialService.collectPolicy(
      operationId: 'REPORT-RECEIPT-1',
      policyId: policy.policyId,
      date: DateTime(2026, 9, 5),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'cash-900',
          method: 'cash',
          amount: 900,
        ),
      ],
    );
    await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'REPORT-INSURER-PAY-1',
      policyId: policy.policyId,
      amount: 700,
      date: DateTime(2026, 9, 6),
      method: 'CASH',
      database: db,
    );
    await InsuranceClaimService.createClaim(
      policyId: policy.policyId,
      claimNumber: 'REPORT-CLM-001',
      lossDate: DateTime(2026, 9, 7),
      database: db,
    );
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('snapshot reconciles posted policy payments claims and balances',
      () async {
    final snapshot = await InsuranceReportingService.snapshot(
      asOf: DateTime(2026, 9, 15),
      executor: db,
    );

    expect(snapshot.postedPolicies, 1);
    expect(snapshot.activePolicies, 1);
    expect(snapshot.expiring30, 1);
    expect(snapshot.openClaims, 1);
    expect(snapshot.sales, 2400);
    expect(snapshot.insurerPayable, 2000);
    expect(snapshot.grossProfit, 400);
    expect(snapshot.customerReceipts, 900);
    expect(snapshot.customerOutstanding, 1500);
    expect(snapshot.insurerPayments, 700);
    expect(snapshot.insurerOutstanding, 1300);
  });

  test('company balances use posted policy and canonical payment links',
      () async {
    final rows = await InsuranceReportingService.companyBalances(executor: db);

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.companyId, companyId);
    expect(row.companyName, 'Reporting Insurance Company');
    expect(row.policyCount, 1);
    expect(row.sales, 2400);
    expect(row.payable, 2000);
    expect(row.profit, 400);
    expect(row.customerReceipts, 900);
    expect(row.customerRefunds, 0);
    expect(row.customerOutstanding, 1500);
    expect(row.insurerPayments, 700);
    expect(row.insurerOutstanding, 1300);
  });
}
