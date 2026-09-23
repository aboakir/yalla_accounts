import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';
import 'package:yalla_accounts/features/insurance_agent/intelligence/screens/insurance_sales_intelligence_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/intelligence/services/insurance_sales_intelligence_service.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';
import 'package:yalla_accounts/features/insurance_agent/producers/services/insurance_producer_portfolio_service.dart';
import 'package:yalla_accounts/features/insurance_agent/quotes/services/insurance_quote_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  Map<String, Object?> employeeRow(String id, String name) => {
        'id': id,
        'full_name': name,
        'employee_code': id,
        'job_title': 'Insurance Producer',
        'hire_date': '2026-01-01',
        'phone': '',
        'email': '',
        'address': '',
        'status': 'active',
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
    temp = await Directory.systemTemp.createTemp('insurance_intelligence_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('snapshot reconciles funnel, sales, renewals and producer leaderboard',
      () async {
    await db.insert('employees', employeeRow('EMP-INT-1', 'Producer Insight'));
    final producerPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['EMPLOYEE', 'EMP-INT-1'],
      limit: 1,
    ))
        .single['party_id']
        .toString();

    final due = await InsuranceCrmService.createProspect(
      name: 'Due Prospect',
      phone: '0599777001',
    );
    await db.update(
      'insurance_prospects',
      {'next_contact_at': DateTime(2026, 9, 22, 9).toIso8601String()},
      where: 'id=?',
      whereArgs: [due.id],
    );

    final buyer = await InsuranceCrmService.createProspect(
      name: 'Issued Buyer',
      phone: '0599777002',
    );
    final clientId = await InsuranceCrmService.convertToInsured(buyer.id);

    final company = await InsuranceMasterDataService.createCompany(
      code: 'INT-INS',
      name: 'Insight Insurance',
      defaultCommissionRate: 10,
    );
    final product = await InsuranceMasterDataService.createProduct(
      companyId: company.id,
      code: 'INT-COMP',
      name: 'Insight Comprehensive',
      productType: 'COMPREHENSIVE',
      defaultCommissionRate: 10,
    );

    Future<InsuranceQuoteResult> makeQuote(String number) {
      return InsuranceQuoteService.createQuote(
        quoteNumber: number,
        partyId: buyer.partyId,
        clientId: clientId,
        prospectId: buyer.id,
        items: [
          InsuranceQuoteItemInput(
            companyId: company.id,
            productId: product.id,
            premium: 2000,
            purchasePrice: 2000,
            salePrice: 2400,
            commissionRate: 10,
          ),
        ],
      );
    }

    Future<String> issue(
      String quoteNumber,
      String policyNumber,
      DateTime endDate,
    ) async {
      final quote = await makeQuote(quoteNumber);
      await InsuranceQuoteService.acceptQuote(
        quoteId: quote.quoteId,
        itemId: quote.itemIds.single,
      );
      final posted = await InsuranceQuoteService.issueAcceptedQuote(
        quoteId: quote.quoteId,
        policyNumber: policyNumber,
        startDate: DateTime(2026, 9, 22),
        endDate: endDate,
        postingDate: DateTime(2026, 9, 22),
        createdBy: 'insurance-owner',
      );
      return posted.policyId;
    }

    final firstPolicy = await issue(
      'INT-Q-001',
      'INT-POL-001',
      DateTime(2026, 10, 10),
    );
    await issue(
      'INT-Q-002',
      'INT-POL-002',
      DateTime(2027, 9, 21),
    );

    await InsuranceProducerPortfolioService.registerEmployeeAsProducer(
      partyId: producerPartyId,
      database: db,
    );
    await InsuranceProducerPortfolioService.assignPolicyToProducer(
      policyId: firstPolicy,
      producerPartyId: producerPartyId,
      database: db,
    );

    final snapshot = await InsuranceSalesIntelligenceService.snapshot(
      executor: db,
      asOf: DateTime(2026, 9, 23, 12),
    );

    expect(snapshot.totalQuotes, 2);
    expect(snapshot.issuedQuotes, 2);
    expect(snapshot.quoteConversionPercent, 100);
    expect(snapshot.activeProspects, 1);
    expect(snapshot.followUpsDue, 1);
    expect(snapshot.postedPolicies, 2);
    expect(snapshot.unassignedPolicies, 1);
    expect(snapshot.expiring30, 1);
    expect(snapshot.sales, 4800);
    expect(snapshot.grossProfit, 800);
    expect(snapshot.grossMarginPercent, 16.67);

    expect(snapshot.topCompanies, hasLength(1));
    final companyRow = snapshot.topCompanies.single;
    expect(companyRow.companyId, company.id);
    expect(companyRow.policyCount, 2);
    expect(companyRow.sales, 4800);
    expect(companyRow.grossProfit, 800);

    expect(snapshot.topProducers, hasLength(1));
    final producerRow = snapshot.topProducers.single;
    expect(producerRow.partyId, producerPartyId);
    expect(producerRow.policyCount, 1);
    expect(producerRow.sales, 2400);
    expect(producerRow.commission, 200);
  });

  testWidgets('screen renders KPI and leaderboard data from injected loader',
      (tester) async {
    const fake = InsuranceSalesIntelligenceSnapshot(
      totalQuotes: 10,
      issuedQuotes: 5,
      activeProspects: 7,
      followUpsDue: 3,
      postedPolicies: 5,
      unassignedPolicies: 2,
      expiring30: 4,
      sales: 12000,
      grossProfit: 2400,
      topCompanies: [
        InsuranceSalesIntelligenceCompanyRow(
          companyId: 11,
          companyName: 'Top Insurance',
          policyCount: 5,
          sales: 12000,
          grossProfit: 2400,
        ),
      ],
      topProducers: [
        InsuranceSalesIntelligenceProducerRow(
          partyId: 'PRODUCER:1',
          producerName: 'Top Producer',
          policyCount: 4,
          sales: 9600,
          commission: 800,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InsuranceSalesIntelligenceScreen(
          loader: () async => fake,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insuranceSalesIntelligenceScreen')),
        findsOneWidget);
    expect(find.text('ذكاء مبيعات التأمين'), findsOneWidget);
    expect(find.text('50.00%'), findsOneWidget);
    expect(find.text('20.00%'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Top Insurance'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Top Insurance'), findsOneWidget);
    expect(find.text('12,000.00'), findsWidgets);

    await tester.dragUntilVisible(
      find.text('Top Producer'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Top Producer'), findsOneWidget);
  });
}
