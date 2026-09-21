import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int clientId;
  late int supplierId;
  late String clientPartyId;
  late String supplierPartyId;
  late String companyId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_core_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'insurance-owner');

    clientId = await db.insert('clients', {
      'name': 'Insurance Customer',
      'type': 'individual',
      'phone': '0599000000',
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

    supplierId = await db.insert('suppliers', {
      'name': 'Test Insurance Company',
      'pid': 'S-INS-TEST',
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
    final now = DateTime.now().toIso8601String();
    final companyDbId = await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'TEST-INS',
      'name': 'Test Insurance Company',
      'default_commission_rate': 0.0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    companyId = companyDbId.toString();
    await db.insert('party_roles', {
      'party_id': supplierPartyId,
      'role': 'INSURANCE_COMPANY',
      'legacy_id': companyId,
      'created_at': now,
    });
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
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

  Future<double> total(String side) async {
    final row = (await db.rawQuery(
      'SELECT COALESCE(SUM($side),0) n FROM gl_lines',
    ))
        .single;
    return (row['n'] as num).toDouble();
  }

  Future<InsurancePolicyPostingResult> issue({
    String operationId = 'POLICY-OP-1',
    String policyNumber = 'POL-001',
  }) {
    return InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: operationId,
        policyNumber: policyNumber,
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId,
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 22),
        endDate: DateTime(2027, 9, 21),
        postingDate: DateTime(2026, 9, 22),
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'insurance-owner',
      ),
      database: db,
    );
  }

  test('v85 schema exposes unified insurance roles and commercial tables',
      () async {
    final roleSql = (await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='party_roles'",
    ))
        .single['sql']
        .toString();
    expect(roleSql, contains('INSURED'));
    expect(roleSql, contains('INSURANCE_COMPANY'));
    expect(roleSql, contains('PROSPECT'));

    for (final table in const [
      'insurance_companies',
      'insurance_products',
      'insurance_quotes',
      'insurance_policy_versions',
      'insurance_claims',
      'insurance_renewals',
      'insurance_alerts',
      'insurance_settlements',
      'insurance_policy_payments',
      'insurance_financial_events',
      'insurance_period_closes',
    ]) {
      final found = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      expect(found, hasLength(1), reason: 'missing $table');
    }
  });

  test('mandatory 2400/2000 scenario reconciles policy AR cash and GL',
      () async {
    final posted = await issue();
    expect(posted.pricing.grossProfit, 400);
    expect(posted.pricing.markupPercent, closeTo(20, 0.000001));
    expect(posted.pricing.marginPercent, closeTo(16.6666667, 0.00001));

    final retry = await issue();
    expect(retry.policyId, posted.policyId);
    expect(retry.glEntryId, posted.glEntryId);
    expect(retry.wasExisting, isTrue);
    expect(
      await db.query(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['INSURANCE_POLICY'],
      ),
      hasLength(1),
    );

    final first = await InsuranceFinancialService.collectPolicy(
      operationId: 'INS-RCPT-1000',
      policyId: posted.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'cash-1000',
          method: 'cash',
          amount: 1000,
        ),
      ],
    );
    expect(first.allocatedAmount, 1000);

    var balances = await InsuranceFinancialService.balances(
      posted.policyId,
      executor: db,
    );
    expect(balances.sale, 2400);
    expect(balances.customerReceipts, 1000);
    expect(balances.customerOutstanding, 1400);
    expect(balances.insurerPayable, 2000);
    expect(await accountBalance('1000'), 1000);
    expect(await accountBalance('1200.C$clientId'), 1400);
    expect(
        await accountBalance('2200.S${supplierId.toString().padLeft(4, '0')}'),
        -2000);
    expect(await accountBalance('4010'), -2400);
    expect(await accountBalance('5010'), 2000);
    expect(await total('debit'), await total('credit'));

    final firstRetry = await InsuranceFinancialService.collectPolicy(
      operationId: 'INS-RCPT-1000',
      policyId: posted.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'cash-1000',
          method: 'cash',
          amount: 1000,
        ),
      ],
    );
    expect(firstRetry.receiptNumber, first.receiptNumber);
    expect(await db.query('receipt_headers'), hasLength(1));

    await InsuranceFinancialService.collectPolicy(
      operationId: 'INS-RCPT-500',
      policyId: posted.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'cash-500',
          method: 'cash',
          amount: 500,
        ),
      ],
    );

    balances = await InsuranceFinancialService.balances(
      posted.policyId,
      executor: db,
    );
    expect(balances.customerReceipts, 1500);
    expect(balances.customerOutstanding, 900);
    expect(await accountBalance('1000'), 1500);
    expect(await accountBalance('1200.C$clientId'), 900);
    expect(await total('debit'), await total('credit'));
  });

  test('late policy failure rolls policy and GL back to zero partial state',
      () async {
    final policyCountBefore =
        (await db.rawQuery('SELECT COUNT(*) n FROM insurance_policies'))
            .single['n'];
    final glCountBefore = (await db.rawQuery(
      "SELECT COUNT(*) n FROM gl_entries WHERE source='INSURANCE_POLICY'",
    ))
        .single['n'];

    await db.execute('''
      CREATE TRIGGER reject_insurance_event
      BEFORE INSERT ON insurance_financial_events
      WHEN NEW.event_type='POLICY_ISSUED'
      BEGIN SELECT RAISE(ABORT,'forced insurance event failure'); END
    ''');

    await expectLater(
      issue(operationId: 'POLICY-FAIL', policyNumber: 'POL-FAIL'),
      throwsA(anything),
    );

    expect(
      (await db.rawQuery('SELECT COUNT(*) n FROM insurance_policies'))
          .single['n'],
      policyCountBefore,
    );
    expect(
      (await db.rawQuery(
        "SELECT COUNT(*) n FROM gl_entries WHERE source='INSURANCE_POLICY'",
      ))
          .single['n'],
      glCountBefore,
    );
    expect(
      await db.query(
        'insurance_policies',
        where: 'operation_id=?',
        whereArgs: ['POLICY-FAIL'],
      ),
      isEmpty,
    );
  });

  test('company payment uses canonical voucher AP and is idempotent', () async {
    final posted = await issue();

    final paid = await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'INS-PAY-1',
      policyId: posted.policyId,
      amount: 500,
      date: DateTime(2026, 9, 22),
      method: 'CASH',
      database: db,
    );
    final retry = await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'INS-PAY-1',
      policyId: posted.policyId,
      amount: 500,
      date: DateTime(2026, 9, 22),
      method: 'CASH',
      database: db,
    );
    expect(retry.id, paid.id);

    final balances = await InsuranceFinancialService.balances(
      posted.policyId,
      executor: db,
    );
    expect(balances.insurerPayments, 500);
    expect(balances.insurerOutstanding, 1500);
    expect(
      await db.query(
        'insurance_policy_payments',
        where: 'policy_id=? AND direction=?',
        whereArgs: [posted.policyId, 'INSURER_PAYMENT'],
      ),
      hasLength(1),
    );
    expect(
        await accountBalance('2200.S${supplierId.toString().padLeft(4, '0')}'),
        -1500);
    expect(await accountBalance('1000'), -500);
    expect(await total('debit'), await total('credit'));
  });
}
