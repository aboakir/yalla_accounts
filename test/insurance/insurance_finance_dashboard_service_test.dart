import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_finance_dashboard_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';

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
    temp =
        await Directory.systemTemp.createTemp('insurance_finance_dashboard_');
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    session = await startAccountingSession(db, 'insurance-finance-owner');

    clientId = await db.insert('clients', {
      'name': 'Finance Customer',
      'type': 'individual',
      'phone': '0599666666',
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
      'name': 'Finance Insurance Company',
      'pid': 'S-FIN-INS',
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
      'code': 'FIN-INS',
      'name': 'Finance Insurance Company',
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
      'normalized_number': VehicleTables.normalizeNumber('FIN-001'),
      'number': 'FIN-001',
      'type': 'Hyundai',
      'model': '2024',
      'client_id': clientId,
      'owner_party_uuid': clientPartyId,
      'is_active': 1,
      'notes': '',
      'created_at': now,
      'updated_at': now,
    });

    policy = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'FIN-POLICY-1',
        policyNumber: 'FIN-POL-001',
        clientId: clientId,
        insuredPartyId: clientPartyId,
        vehicleId: vehicleId,
        vehiclePlate: 'FIN-001',
        companyId: companyId.toString(),
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2027, 8, 31),
        postingDate: DateTime(2026, 9, 1),
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'insurance-finance-owner',
      ),
      database: db,
    );

    await InsuranceFinancialService.collectPolicy(
      operationId: 'FIN-RCPT-1',
      policyId: policy.policyId,
      date: DateTime(2026, 9, 2),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'cash-1200',
          method: 'cash',
          amount: 1200,
        ),
      ],
    );
    await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'FIN-PAY-1',
      policyId: policy.policyId,
      amount: 500,
      date: DateTime(2026, 9, 3),
      method: 'CASH',
      database: db,
    );
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('policy balances reconcile canonical receipt and insurer payment',
      () async {
    final rows =
        await InsuranceFinanceDashboardService.policyBalances(executor: db);
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.policyId, policy.policyId);
    expect(row.policyNumber, 'FIN-POL-001');
    expect(row.insuredName, 'Finance Customer');
    expect(row.companyName, 'Finance Insurance Company');
    expect(row.sale, 2400);
    expect(row.customerReceipts, 1200);
    expect(row.customerOutstanding, 1200);
    expect(row.insurerPayable, 2000);
    expect(row.insurerPayments, 500);
    expect(row.insurerOutstanding, 1500);
  });

  test('recent transactions expose posted canonical receipt and voucher links',
      () async {
    final rows = await InsuranceFinanceDashboardService.recentTransactions(
      executor: db,
      limit: 10,
    );
    expect(rows, hasLength(2));
    expect(rows.map((e) => e.direction).toSet(),
        {'CUSTOMER_RECEIPT', 'INSURER_PAYMENT'});
    final receipt = rows.singleWhere((e) => e.direction == 'CUSTOMER_RECEIPT');
    expect(receipt.amount, 1200);
    expect(receipt.receiptNumber, isNotNull);
    final insurer = rows.singleWhere((e) => e.direction == 'INSURER_PAYMENT');
    expect(insurer.amount, 500);
    expect(insurer.voucherId, isNotNull);
  });

  test('recent transaction limit is guarded', () {
    expect(
      () => InsuranceFinanceDashboardService.recentTransactions(
        executor: db,
        limit: 0,
      ),
      throwsArgumentError,
    );
  });
}
