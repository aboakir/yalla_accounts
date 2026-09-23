import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_endorsement_refund_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late String policyId;
  late int clientId;
  late int supplierId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_stage8_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/stage8.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'insurance-stage8-owner');

    clientId = await db.insert('clients', {
      'name': 'Stage 8 Customer',
      'type': 'individual',
      'phone': '0599888100',
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
    final now = DateTime(2026, 9, 23).toIso8601String();
    await db.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': now,
    });

    supplierId = await db.insert('suppliers', {
      'name': 'Stage 8 Insurance Company',
      'pid': 'S-STAGE8',
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
      'code': 'STAGE8-INS',
      'name': 'Stage 8 Insurance Company',
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

    final policy = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'STAGE8-POLICY',
        policyNumber: 'STAGE8-POL-001',
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId.toString(),
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2027, 8, 31),
        postingDate: DateTime(2026, 9, 1),
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'insurance-stage8-owner',
      ),
      database: db,
    );
    policyId = policy.policyId;
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

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

  Future<void> expectBalanced() async {
    final row = (await db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c '
      'FROM gl_lines',
    ))
        .single;
    expect(
      (row['d'] as num).toDouble(),
      closeTo((row['c'] as num).toDouble(), 0.001),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  }

  test('reduction endorsement creates customer credit then canonical refund',
      () async {
    await InsuranceFinancialService.collectPolicy(
      operationId: 'STAGE8-FULL-RECEIPT',
      policyId: policyId,
      date: DateTime(2026, 9, 2),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'stage8-cash-full',
          method: 'cash',
          amount: 2400,
        ),
      ],
    );
    final endorsement = await InsuranceEndorsementRefundService.postEndorsement(
      operationId: 'STAGE8-REDUCE',
      policyId: policyId,
      endorsementType: 'REDUCTION',
      effectiveDate: DateTime(2026, 9, 3),
      deltaSale: -400,
      deltaCost: -300,
      database: db,
    );
    expect(endorsement.customerDelta, -400);
    expect(endorsement.insurerDelta, -300);

    var balances = await InsuranceFinancialService.balances(
      policyId,
      executor: db,
    );
    expect(balances.sale, 2000);
    expect(balances.customerReceipts, 2400);
    expect(balances.customerOutstanding, -400);
    expect(balances.insurerPayable, 1700);

    final refund = await InsuranceEndorsementRefundService.refundCustomer(
      operationId: 'STAGE8-REFUND',
      policyId: policyId,
      amount: 400,
      date: DateTime(2026, 9, 4),
      method: 'CASH',
      database: db,
    );
    expect(refund.partyType, 'CLIENT');
    expect(refund.partyId, clientId.toString());

    balances = await InsuranceFinancialService.balances(
      policyId,
      executor: db,
    );
    expect(balances.customerReceipts, 2000);
    expect(balances.customerOutstanding, 0);
    expect(await accountBalance('1200.C$clientId'), closeTo(0, 0.001));
    final refundLinks = await db.query(
      'insurance_policy_payments',
      where: 'policy_id=? AND direction=?',
      whereArgs: [policyId, 'REFUND'],
    );
    expect(refundLinks, hasLength(1));
    expect(refundLinks.single['status'], 'POSTED');
    await expectBalanced();

    await InsuranceEndorsementRefundService.reverseRefund(
      voucherId: refund.id,
      reason: 'Refund correction',
      database: db,
    );
    balances = await InsuranceFinancialService.balances(
      policyId,
      executor: db,
    );
    expect(balances.customerOutstanding, -400);
    expect(
      (await db.query(
        'insurance_policy_payments',
        where: 'voucher_id=?',
        whereArgs: [refund.id],
      ))
          .single['status'],
      'REVERSED',
    );

    final reversal = await InsuranceEndorsementRefundService.reverseEndorsement(
      endorsementId: endorsement.id,
      reason: 'Restore original cover',
      database: db,
    );
    expect(reversal, greaterThan(0));

    balances = await InsuranceFinancialService.balances(
      policyId,
      executor: db,
    );
    expect(balances.sale, 2400);
    expect(balances.customerOutstanding, 0);
    expect(balances.insurerPayable, 2000);
    expect(await accountBalance('1200.C$clientId'), closeTo(0, 0.001));
    await expectBalanced();
  });
  test('positive endorsement is idempotent and updates AR AP tax profit',
      () async {
    final first = await InsuranceEndorsementRefundService.postEndorsement(
      operationId: 'STAGE8-ADD',
      policyId: policyId,
      endorsementType: 'ADDITION',
      effectiveDate: DateTime(2026, 9, 5),
      deltaSale: 200,
      deltaCost: 100,
      deltaTax: 20,
      database: db,
    );
    final retry = await InsuranceEndorsementRefundService.postEndorsement(
      operationId: 'STAGE8-ADD',
      policyId: policyId,
      endorsementType: 'ADDITION',
      effectiveDate: DateTime(2026, 9, 5),
      deltaSale: 200,
      deltaCost: 100,
      deltaTax: 20,
      database: db,
    );
    expect(retry.wasExisting, isTrue);
    expect(retry.glEntryId, first.glEntryId);

    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [policyId],
      limit: 1,
    ))
        .single;
    expect(policy['net_sale_amount'], 2620.0);
    expect(policy['net_insurer_payable'], 2100.0);
    expect(policy['tax'], 20.0);
    expect(policy['gross_profit'], 500.0);

    expect(await accountBalance('1200.C$clientId'), closeTo(2620, 0.001));
    expect(
      await accountBalance(
        '2200.S${supplierId.toString().padLeft(4, '0')}',
      ),
      closeTo(-2100, 0.001),
    );
    expect(await accountBalance('2105'), closeTo(-20, 0.001));
    expect(await db.query('insurance_endorsements'), hasLength(1));
    await expectBalanced();

    await expectLater(
      InsuranceEndorsementRefundService.postEndorsement(
        operationId: 'STAGE8-ADD',
        policyId: policyId,
        endorsementType: 'ADDITION',
        effectiveDate: DateTime(2026, 9, 5),
        deltaSale: 201,
        deltaCost: 100,
        deltaTax: 20,
        database: db,
      ),
      throwsStateError,
    );
  });
}
