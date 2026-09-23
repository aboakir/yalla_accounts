import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/account_statements/customers/services/customer_account_statement_service.dart';
import 'package:yalla_accounts/features/account_statements/suppliers/services/supplier_statement_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_finance_dashboard_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

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
    temp = await Directory.systemTemp.createTemp('insurance_stage4_cross_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/stage4.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'insurance-stage4-owner');

    clientId = await db.insert('clients', {
      'name': 'Stage 4 Customer',
      'type': 'individual',
      'phone': '0599444400',
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
      'name': 'Stage 4 Insurance Company',
      'pid': 'S-STAGE4',
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

    final now = DateTime(2026, 9, 23).toIso8601String();
    companyId = (await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'STAGE4-INS',
      'name': 'Stage 4 Insurance Company',
      'default_commission_rate': 10.0,
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

  Future<void> expectBalancedGl() async {
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

  test(
      'unified pricing stays identical across AR AP cheque voucher dashboard and reversals',
      () async {
    final policy = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'STAGE4-POLICY-1',
        policyNumber: 'STAGE4-POL-001',
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId,
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: DateTime(2026, 9, 23),
        endDate: DateTime(2027, 9, 22),
        postingDate: DateTime(2026, 9, 23),
        purchasePrice: 2000,
        salePrice: 2400,
        basePremium: 1800,
        discount: 50,
        fees: 30,
        tax: 100,
        commissionRate: 10,
        directCost: 80,
        createdBy: 'insurance-stage4-owner',
      ),
      database: db,
    );

    expect(policy.pricing.customerTotalAmount, 2480);
    expect(policy.pricing.netRevenueAmount, 2380);
    expect(policy.pricing.commissionAmount, 180);
    expect(policy.pricing.grossProfit, 300);

    final receipt = await InsuranceFinancialService.collectPolicy(
      operationId: 'STAGE4-RECEIPT-1',
      policyId: policy.policyId,
      date: DateTime(2026, 9, 23),
      database: db,
      instruments: [
        const ReceiptInstrumentInput(
          instrumentKey: 'STAGE4-CASH-1000',
          method: 'cash',
          amount: 1000,
        ),
        ReceiptInstrumentInput(
          instrumentKey: 'STAGE4-CHEQUE-480',
          method: 'cheque',
          amount: 480,
          chequeDraft: {
            'cheque_no': 'STAGE4-CHQ-480',
            'drawer_name': 'Stage 4 Customer',
            'bank_name': 'Stage 4 Bank',
            'issue_date': DateTime(2026, 9, 23).toIso8601String(),
            'due_date': DateTime(2026, 12, 23).toIso8601String(),
          },
        ),
      ],
    );
    final voucher =
        await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: 'STAGE4-INSURER-PAY-1',
      policyId: policy.policyId,
      amount: 500,
      date: DateTime(2026, 9, 23),
      method: 'CASH',
      database: db,
    );

    var balances = await InsuranceFinancialService.balances(
      policy.policyId,
      executor: db,
    );
    var customer = await CustomerAccountStatementService.load(
      clientId: clientId,
      executor: db,
    );
    var supplier = await SupplierStatementService.load(
      supplierId: supplierId.toString(),
      executor: db,
    );
    var partyBalances = await PartyFinancialService.balances(executor: db);
    var dashboard =
        await InsuranceFinanceDashboardService.policyBalances(executor: db);

    expect(balances.customerReceipts, 1480);
    expect(balances.customerOutstanding, 1000);
    expect(customer.closingBalance, 1000);
    expect(
      partyBalances
          .singleWhere((row) => row.customerLegacyId == clientId.toString())
          .receivableBalance,
      1000,
    );
    expect(balances.insurerPayments, 500);
    expect(balances.insurerOutstanding, 1500);
    expect(supplier.closingBalance, 1500);
    expect(
      partyBalances
          .singleWhere((row) => row.supplierLegacyId == supplierId.toString())
          .payableBalance,
      1500,
    );

    final dashboardRow = dashboard.single;
    expect(dashboardRow.sale, 2480);
    expect(dashboardRow.customerReceipts, 1480);
    expect(dashboardRow.customerOutstanding, 1000);
    expect(dashboardRow.insurerPayable, 2000);
    expect(dashboardRow.insurerPayments, 500);
    expect(dashboardRow.insurerOutstanding, 1500);

    final transactions =
        await InsuranceFinanceDashboardService.recentTransactions(
      executor: db,
      limit: 20,
    );
    expect(
      transactions
          .where((row) => row.direction == 'CUSTOMER_RECEIPT')
          .fold<double>(0, (sum, row) => sum + row.amount),
      1480,
    );
    expect(
      transactions
          .where((row) => row.direction == 'INSURER_PAYMENT')
          .fold<double>(0, (sum, row) => sum + row.amount),
      500,
    );

    expect(await accountBalance('1000'), 500);
    expect(await accountBalance('1020'), 480);
    expect(await accountBalance('1200.C$clientId'), 1000);
    expect(
      await accountBalance('2200.S${supplierId.toString().padLeft(4, '0')}'),
      -1500,
    );
    expect(await accountBalance('4010'), -2380);
    expect(await accountBalance('2105'), -100);
    expect(await accountBalance('5010'), 2000);
    expect(await accountBalance('5030'), 80);
    expect(await accountBalance('2190'), -80);
    await expectBalancedGl();
    await PaymentService.reverseReceipt(
      receipt.receiptNumber,
      reason: 'Stage 4 customer receipt reversal',
      database: db,
    );

    balances = await InsuranceFinancialService.balances(
      policy.policyId,
      executor: db,
    );
    customer = await CustomerAccountStatementService.load(
      clientId: clientId,
      executor: db,
    );
    dashboard =
        await InsuranceFinanceDashboardService.policyBalances(executor: db);
    expect(balances.customerReceipts, 0);
    expect(balances.customerOutstanding, 2480);
    expect(customer.closingBalance, 2480);
    expect(dashboard.single.customerOutstanding, 2480);
    expect(await accountBalance('1020'), 0);
    expect(await accountBalance('1200.C$clientId'), 2480);
    expect((await db.query('cheques')).single['status'], 'cancelled');

    await VoucherPaymentService.reverseVoucher(
      voucher.id,
      reason: 'Stage 4 insurer voucher reversal',
      database: db,
    );

    balances = await InsuranceFinancialService.balances(
      policy.policyId,
      executor: db,
    );
    supplier = await SupplierStatementService.load(
      supplierId: supplierId.toString(),
      executor: db,
    );
    partyBalances = await PartyFinancialService.balances(executor: db);
    dashboard =
        await InsuranceFinanceDashboardService.policyBalances(executor: db);
    expect(balances.insurerPayments, 0);
    expect(balances.insurerOutstanding, 2000);
    expect(supplier.closingBalance, 2000);
    expect(
      partyBalances
          .singleWhere((row) => row.supplierLegacyId == supplierId.toString())
          .payableBalance,
      2000,
    );
    expect(dashboard.single.insurerOutstanding, 2000);
    expect(await accountBalance('1000'), 0);
    await expectBalancedGl();

    final cancellationGl = await InsuranceFinancialService.cancelPolicy(
      policyId: policy.policyId,
      reason: 'Stage 4 full lifecycle cancellation',
    );
    expect(cancellationGl, greaterThan(0));
    customer = await CustomerAccountStatementService.load(
      clientId: clientId,
      executor: db,
    );
    supplier = await SupplierStatementService.load(
      supplierId: supplierId.toString(),
      executor: db,
    );
    partyBalances = await PartyFinancialService.balances(executor: db);
    dashboard =
        await InsuranceFinanceDashboardService.policyBalances(executor: db);

    expect(customer.closingBalance, 0);
    expect(supplier.closingBalance, 0);
    expect(
      partyBalances
          .singleWhere((row) => row.customerLegacyId == clientId.toString())
          .receivableBalance,
      0,
    );
    expect(
      partyBalances
          .singleWhere((row) => row.supplierLegacyId == supplierId.toString())
          .payableBalance,
      0,
    );
    expect(dashboard, isEmpty);
    expect(await accountBalance('1200.C$clientId'), 0);
    expect(
      await accountBalance('2200.S${supplierId.toString().padLeft(4, '0')}'),
      0,
    );
    expect(await accountBalance('4010'), 0);
    expect(await accountBalance('2105'), 0);
    expect(await accountBalance('5010'), 0);
    expect(await accountBalance('5030'), 0);
    expect(await accountBalance('2190'), 0);
    await expectBalancedGl();
  });
}
