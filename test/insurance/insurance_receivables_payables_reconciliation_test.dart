import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/account_statements/customers/services/customer_account_statement_service.dart';
import 'package:yalla_accounts/features/account_statements/suppliers/services/supplier_statement_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

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
    temp = await Directory.systemTemp.createTemp('insurance_reconcile_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'insurance-reconcile-owner');

    clientId = await db.insert('clients', {
      'name': 'Insurance Reconcile Customer',
      'type': 'individual',
      'phone': '0599111111',
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
      'name': 'Insurance Reconcile Company',
      'pid': 'S-INS-REC',
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
    companyId = (await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'REC-INS',
      'name': 'Insurance Reconcile Company',
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

  test(
      'fully settled policy reconciles customer company statements and GL to zero',
      () async {
    final posted = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'STAGE14-ZERO-POLICY',
        policyNumber: 'STAGE14-ZERO-001',
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
        createdBy: 'insurance-reconcile-owner',
      ),
      database: db,
    );

    await InsuranceFinancialService.collectPolicy(
      operationId: 'STAGE14-ZERO-RECEIPT',
      policyId: posted.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'stage14-zero-cash',
          method: 'cash',
          amount: 2400,
        ),
      ],
    );
    await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'STAGE14-ZERO-PAYMENT',
      policyId: posted.policyId,
      amount: 2000,
      date: DateTime(2026, 9, 22),
      method: 'CASH',
      database: db,
    );

    final policyBalances = await InsuranceFinancialService.balances(
      posted.policyId,
      executor: db,
    );
    final customer = await CustomerAccountStatementService.load(
      clientId: clientId,
      executor: db,
    );
    final supplier = await SupplierStatementService.load(
      supplierId: supplierId.toString(),
      executor: db,
    );
    final partyBalances = await PartyFinancialService.balances(executor: db);
    final customerSummary = partyBalances.singleWhere(
      (row) => row.customerLegacyId == clientId.toString(),
    );
    final supplierSummary = partyBalances.singleWhere(
      (row) => row.supplierLegacyId == supplierId.toString(),
    );

    expect(policyBalances.customerOutstanding, 0);
    expect(policyBalances.insurerOutstanding, 0);
    expect(customer.closingBalance, 0);
    expect(supplier.closingBalance, 0);
    expect(customerSummary.receivableBalance, 0);
    expect(supplierSummary.payableBalance, 0);
    expect(await accountBalance('1200.C$clientId'), 0);
    expect(
      await accountBalance(
        '2200.S${supplierId.toString().padLeft(4, '0')}',
      ),
      0,
    );
    final gl = (await db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) debit, COALESCE(SUM(credit),0) credit FROM gl_lines',
    ))
        .single;
    expect(
      ((gl['debit'] as num).toDouble() - (gl['credit'] as num).toDouble())
          .abs(),
      0,
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('policy customer and insurer balances reconcile to statements and GL',
      () async {
    final posted = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'P15-POLICY-1',
        policyNumber: 'P15-0001',
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
        createdBy: 'insurance-reconcile-owner',
      ),
      database: db,
    );

    await InsuranceFinancialService.collectPolicy(
      operationId: 'P15-RECEIPT-1000',
      policyId: posted.policyId,
      date: DateTime(2026, 9, 22),
      database: db,
      instruments: const [
        ReceiptInstrumentInput(
          instrumentKey: 'P15-CASH-1000',
          method: 'cash',
          amount: 1000,
        ),
      ],
    );

    await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'P15-PAYMENT-500',
      policyId: posted.policyId,
      amount: 500,
      date: DateTime(2026, 9, 22),
      method: 'CASH',
      database: db,
    );

    final policyBalances = await InsuranceFinancialService.balances(
      posted.policyId,
      executor: db,
    );
    final customer = await CustomerAccountStatementService.load(
      clientId: clientId,
      executor: db,
    );
    final supplier = await SupplierStatementService.load(
      supplierId: supplierId.toString(),
      executor: db,
    );
    final partyBalances = await PartyFinancialService.balances(executor: db);
    final customerSummary = partyBalances.singleWhere(
      (row) => row.customerLegacyId == clientId.toString(),
    );
    final supplierSummary = partyBalances.singleWhere(
      (row) => row.supplierLegacyId == supplierId.toString(),
    );

    expect(policyBalances.customerOutstanding, 1400);
    expect(customer.closingBalance, 1400);
    expect(customerSummary.receivableBalance, 1400);
    expect(await accountBalance('1200.C$clientId'), 1400);

    expect(policyBalances.insurerOutstanding, 1500);
    expect(supplier.closingBalance, 1500);
    expect(supplierSummary.payableBalance, 1500);
    expect(
      await accountBalance(
        '2200.S${supplierId.toString().padLeft(4, '0')}',
      ),
      -1500,
    );

    expect(
      (policyBalances.customerOutstanding - customer.closingBalance).abs(),
      0.0,
    );
    expect(
      (policyBalances.insurerOutstanding - supplier.closingBalance).abs(),
      0.0,
    );
  });
}
