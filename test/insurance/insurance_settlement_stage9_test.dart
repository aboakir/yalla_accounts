import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_settlement_service.dart';

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

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp =
        await Directory.systemTemp.createTemp('insurance_stage9_settlement_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/stage9.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'insurance-stage9-owner');

    clientId = await db.insert('clients', {
      'name': 'Stage 9 Customer',
      'type': 'individual',
      'phone': '0599999100',
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
      'name': 'Stage 9 Insurance Company',
      'pid': 'S-STAGE9',
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
      'code': 'STAGE9-INS',
      'name': 'Stage 9 Insurance Company',
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
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<InsurancePolicyPostingResult> issue(
    String operation,
    String number,
    DateTime postingDate,
  ) {
    return InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: operation,
        policyNumber: number,
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId.toString(),
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: postingDate,
        endDate: DateTime(
          postingDate.year + 1,
          postingDate.month,
          postingDate.day,
        ),
        postingDate: postingDate,
        purchasePrice: 2000,
        salePrice: 2400,
        basePremium: 2000,
        commissionRate: 10,
        createdBy: 'insurance-stage9-owner',
      ),
      database: db,
    );
  }

  test('settlement builds from policy outstanding and canonical vouchers',
      () async {
    final first = await issue(
      'STAGE9-P1',
      'STAGE9-POL-001',
      DateTime(2026, 9, 5),
    );
    final second = await issue(
      'STAGE9-P2',
      'STAGE9-POL-002',
      DateTime(2026, 9, 10),
    );
    await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'STAGE9-PREV-PAY',
      policyId: first.policyId,
      amount: 500,
      date: DateTime(2026, 9, 12),
      method: 'CASH',
      database: db,
    );

    final settlement = await InsuranceSettlementService.buildSettlement(
      operationId: 'STAGE9-SET-SEP',
      companyId: companyId,
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      database: db,
    );
    expect(settlement.status, 'DRAFT');
    expect(settlement.grossPolicies, 4000);
    expect(settlement.previousPayments, 500);
    expect(settlement.payable, 3500);
    expect(settlement.commission, 400);
    final items = await InsuranceSettlementService.items(
      settlement.id,
      executor: db,
    );
    expect(items, hasLength(2));
    expect(
      items.map((item) => item.amount).reduce((a, b) => a + b),
      3500,
    );

    final retry = await InsuranceSettlementService.buildSettlement(
      operationId: 'STAGE9-SET-SEP',
      companyId: companyId,
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      database: db,
    );
    expect(retry.id, settlement.id);
    expect(await db.query('insurance_settlements'), hasLength(1));

    final posted = await InsuranceSettlementService.postSettlement(
      settlement.id,
      database: db,
    );
    expect(posted.status, 'POSTED');

    final part = await InsuranceSettlementService.paySettlement(
      operationId: 'STAGE9-SET-PAY-1',
      settlementId: settlement.id,
      amount: 1000,
      date: DateTime(2026, 10, 1),
      method: 'CASH',
      database: db,
    );
    expect(
      await InsuranceSettlementService.paidAmount(
        settlement.id,
        executor: db,
      ),
      1000,
    );
    var stored = (await db.query(
      'insurance_settlements',
      where: 'id=?',
      whereArgs: [settlement.id],
      limit: 1,
    ))
        .single;
    expect(stored['status'], 'POSTED');

    final finalPay = await InsuranceSettlementService.paySettlement(
      operationId: 'STAGE9-SET-PAY-2',
      settlementId: settlement.id,
      amount: 2500,
      date: DateTime(2026, 10, 2),
      method: 'CASH',
      database: db,
    );
    expect(
      await InsuranceSettlementService.paidAmount(
        settlement.id,
        executor: db,
      ),
      3500,
    );

    final finalRetry = await InsuranceSettlementService.paySettlement(
      operationId: 'STAGE9-SET-PAY-2',
      settlementId: settlement.id,
      amount: 2500,
      date: DateTime(2026, 10, 2),
      method: 'CASH',
      database: db,
    );
    expect(finalRetry.id, finalPay.id);
    expect(
      await InsuranceSettlementService.paidAmount(
        settlement.id,
        executor: db,
      ),
      3500,
    );
    expect(
      await db.query(
        'insurance_policy_payments',
        where: 'voucher_id=?',
        whereArgs: [finalPay.id],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['VOUCHER', finalPay.id],
      ),
      hasLength(1),
    );

    stored = (await db.query(
      'insurance_settlements',
      where: 'id=?',
      whereArgs: [settlement.id],
      limit: 1,
    ))
        .single;
    expect(stored['status'], 'PAID');

    await expectLater(
      InsuranceSettlementService.paySettlement(
        operationId: 'STAGE9-OVER',
        settlementId: settlement.id,
        amount: 1,
        date: DateTime(2026, 10, 3),
        method: 'CASH',
        database: db,
      ),
      throwsStateError,
    );

    await InsuranceSettlementService.reverseSettlementPayment(
      settlementId: settlement.id,
      voucherId: finalPay.id,
      reason: 'Settlement correction',
      database: db,
    );
    expect(
      await InsuranceSettlementService.paidAmount(
        settlement.id,
        executor: db,
      ),
      1000,
    );
    stored = (await db.query(
      'insurance_settlements',
      where: 'id=?',
      whereArgs: [settlement.id],
      limit: 1,
    ))
        .single;
    expect(stored['status'], 'POSTED');

    expect(
      (await db.query(
        'insurance_policy_payments',
        where: 'voucher_id=?',
        whereArgs: [part.id],
      ))
          .single['settlement_id'],
      settlement.id,
    );
    expect(second.policyId, isNotEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
