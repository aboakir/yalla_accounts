import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/producers/services/insurance_producer_portfolio_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late String producerPartyId;
  late int clientId;
  late String clientPartyId;
  late int supplierId;
  late String supplierPartyId;
  late int companyId;
  late int vehicleId;

  Map<String, Object?> employeeRow(String id, String name, {String status = 'active'}) => {
        'id': id,
        'full_name': name,
        'employee_code': id,
        'job_title': 'Insurance Producer',
        'hire_date': '2026-01-01',
        'phone': '',
        'email': '',
        'address': '',
        'status': status,
        'base_salary': 1200.0,
        'allowances': 0.0,
        'deductions': 0.0,
        'advances': 0.0,
        'total_work_days': 0,
        'total_hours': 0.0,
        'absences': 0,
        'late_days': 0,
        'notes': '',
        'created_at': '2026-01-01T00:00:00Z',
        'payment_method': 'cash',
        'work_days_per_week': 6,
        'hours_per_day': 8,
      };

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_producer_');
    db = await DatabaseMigration.initDatabase(pathOverride: '${temp.path}/test.db');
    session = await startAccountingSession(db, 'insurance-owner');

    await db.insert('employees', employeeRow('EMP-PROD-1', 'Producer One'));
    await db.insert('employees', employeeRow('EMP-OFF-1', 'Inactive Employee', status: 'inactive'));
    producerPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['EMPLOYEE', 'EMP-PROD-1'],
      limit: 1,
    )).single['party_id'].toString();

    clientId = await db.insert('clients', {
      'name': 'Producer Portfolio Customer',
      'type': 'individual',
      'phone': '0599123456',
    });
    clientPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['CUSTOMER', clientId.toString()],
      limit: 1,
    )).single['party_id'].toString();
    await db.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': DateTime.now().toIso8601String(),
    });

    supplierId = await db.insert('suppliers', {'name': 'Producer Test Insurance'});
    supplierPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['SUPPLIER', supplierId.toString()],
      limit: 1,
    )).single['party_id'].toString();
    final now = DateTime.now().toIso8601String();
    companyId = await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'PROD-TEST',
      'name': 'Producer Test Insurance',
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
      'normalized_number': VehicleTables.normalizeNumber('PROD-001'),
      'number': 'PROD-001',
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

  Future<InsurancePolicyPostingResult> issue(String op, String number) {
    return InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: op,
        policyNumber: number,
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId.toString(),
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        vehicleId: vehicleId,
        vehiclePlate: 'PROD-001',
        startDate: DateTime(2026, 9, 22),
        endDate: DateTime(2027, 9, 21),
        postingDate: DateTime(2026, 9, 22),
        purchasePrice: 2000,
        salePrice: 2400,
        commissionRate: 10,
        createdBy: 'insurance-owner',
      ),
      database: db,
    );
  }

  test('active employee becomes producer and inactive employee is not eligible', () async {
    var snapshot = await InsuranceProducerPortfolioService.load(executor: db);
    expect(snapshot.eligibleEmployees.map((e) => e.partyId), contains(producerPartyId));
    expect(snapshot.eligibleEmployees.map((e) => e.name), isNot(contains('Inactive Employee')));

    await InsuranceProducerPortfolioService.registerEmployeeAsProducer(
      partyId: producerPartyId,
      database: db,
    );
    snapshot = await InsuranceProducerPortfolioService.load(executor: db);
    expect(snapshot.portfolios, hasLength(1));
    expect(snapshot.portfolios.single.producerName, 'Producer One');
    expect(snapshot.eligibleEmployees, isEmpty);

    await InsuranceProducerPortfolioService.registerEmployeeAsProducer(
      partyId: producerPartyId,
      database: db,
    );
    expect(
      await db.query('party_roles', where: 'party_id=? AND role=?', whereArgs: [producerPartyId, 'PRODUCER']),
      hasLength(1),
    );
  });

  test('posted policy can be assigned and portfolio totals reconcile receipts', () async {
    final posted = await issue('PROD-POL-1', 'PROD-POL-001');
    var snapshot = await InsuranceProducerPortfolioService.load(executor: db);
    expect(snapshot.unassignedPolicies.map((p) => p.policyId), contains(posted.policyId));

    await InsuranceProducerPortfolioService.registerEmployeeAsProducer(
      partyId: producerPartyId,
      database: db,
    );
    await InsuranceProducerPortfolioService.assignPolicyToProducer(
      policyId: posted.policyId,
      producerPartyId: producerPartyId,
      database: db,
    );
    await InsuranceFinancialService.collectPolicy(
      operationId: 'PROD-RCPT-1',
      policyId: posted.policyId,
      date: DateTime(2026, 9, 22),
      instruments: const [
        ReceiptInstrumentInput(instrumentKey: 'cash-600', method: 'cash', amount: 600),
      ],
      database: db,
    );

    snapshot = await InsuranceProducerPortfolioService.load(executor: db);
    expect(snapshot.unassignedPolicies, isEmpty);
    expect(snapshot.portfolios, hasLength(1));
    final row = snapshot.portfolios.single;
    expect(row.policyCount, 1);
    expect(row.sales, 2400);
    expect(row.customerReceipts, 600);
    expect(row.customerOutstanding, 1800);
    expect(row.commission, 200);
  });

  test('assignment rejects a Party that is not an active producer', () async {
    final posted = await issue('PROD-POL-2', 'PROD-POL-002');
    await expectLater(
      InsuranceProducerPortfolioService.assignPolicyToProducer(
        policyId: posted.policyId,
        producerPartyId: producerPartyId,
        database: db,
      ),
      throwsStateError,
    );
  });
}

