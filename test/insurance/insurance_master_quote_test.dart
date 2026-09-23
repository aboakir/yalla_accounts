import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';
import 'package:yalla_accounts/features/insurance_agent/quotes/services/insurance_quote_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_quote_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/quote.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('company is one Supplier + Party + INSURANCE_COMPANY role', () async {
    final company = await InsuranceMasterDataService.createCompany(
      code: 'QA-INS',
      name: 'شركة اختبار التأمين',
      phone: '022222222',
      defaultCommissionRate: 10,
    );

    expect(company.id, greaterThan(0));
    expect(company.supplierId, greaterThan(0));
    final companies = await InsuranceMasterDataService.listCompanies();
    expect(companies.any((item) => item.id == company.id), isTrue);

    final supplierRole = await db.query(
      'party_roles',
      where: 'party_id=? AND role=? AND legacy_id=?',
      whereArgs: [
        company.partyId,
        'SUPPLIER',
        company.supplierId.toString(),
      ],
    );
    final companyRole = await db.query(
      'party_roles',
      where: 'party_id=? AND role=? AND legacy_id=?',
      whereArgs: [
        company.partyId,
        'INSURANCE_COMPANY',
        company.id.toString(),
      ],
    );
    expect(supplierRole, hasLength(1));
    expect(companyRole, hasLength(1));

    final product = await InsuranceMasterDataService.createProduct(
      companyId: company.id,
      code: 'TPL',
      name: 'طرف ثالث',
      productType: 'THIRD_PARTY',
      defaultCommissionRate: 10,
    );
    expect(product.companyId, company.id);

    final coverageId = await InsuranceMasterDataService.createCoverage(
      productId: product.id,
      code: 'BASIC',
      name: 'تغطية أساسية',
      deductible: 100,
    );
    expect(
      await db.query(
        'insurance_coverages',
        where: 'id=? AND product_id=?',
        whereArgs: [coverageId, product.id],
      ),
      hasLength(1),
    );
  });

  test('listProducts bootstraps defaults for legacy company without products',
      () async {
    final company = await InsuranceMasterDataService.createCompany(
      code: 'AUTO-PRODUCTS',
      name: 'Auto Products Insurance',
      defaultCommissionRate: 12.5,
    );

    final before = await db.query(
      'insurance_products',
      where: 'company_id=?',
      whereArgs: [company.id],
    );
    expect(before, isEmpty);

    final products = await InsuranceMasterDataService.listProducts(
      companyId: company.id,
    );

    expect(products, hasLength(2));
    expect(
      products.map((item) => item.productType).toSet(),
      {'THIRD_PARTY', 'COMPREHENSIVE'},
    );
    expect(products.every((item) => item.isActive), isTrue);
    expect(
      products.every((item) => item.defaultCommissionRate == 12.5),
      isTrue,
    );

    final second = await InsuranceMasterDataService.listProducts(
      companyId: company.id,
    );
    expect(second, hasLength(2));

    final persisted = await db.query(
      'insurance_products',
      where: 'company_id=?',
      whereArgs: [company.id],
    );
    expect(persisted, hasLength(2));
  });

  test('quote has zero GL until accepted quote becomes a policy', () async {
    final prospect = await InsuranceCrmService.createProspect(
      name: 'عميل عرض سعر',
      phone: '0599555000',
    );
    final clientId = await InsuranceCrmService.convertToInsured(prospect.id);

    final company = await InsuranceMasterDataService.createCompany(
      code: 'Q-INS',
      name: 'شركة عرض سعر',
      defaultCommissionRate: 10,
    );
    final product = await InsuranceMasterDataService.createProduct(
      companyId: company.id,
      code: 'COMP',
      name: 'شامل',
      productType: 'COMPREHENSIVE',
      defaultCommissionRate: 10,
    );

    final beforeGl = (await db.rawQuery(
      'SELECT COUNT(*) n FROM gl_entries',
    ))
        .single['n'];

    final quote = await InsuranceQuoteService.createQuote(
      quoteNumber: 'Q-0001',
      partyId: prospect.partyId,
      clientId: clientId,
      prospectId: prospect.id,
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

    expect(
      (await db.rawQuery('SELECT COUNT(*) n FROM gl_entries')).single['n'],
      beforeGl,
      reason: 'creating a quote must never post accounting',
    );
    final summaries = await InsuranceQuoteService.listQuotes(executor: db);
    expect(summaries, hasLength(1));
    expect(summaries.single.id, quote.quoteId);
    expect(summaries.single.quoteNumber, 'Q-0001');
    expect(summaries.single.itemCount, 1);
    expect(summaries.single.status, 'DRAFT');

    final offers = await InsuranceQuoteService.listQuoteItems(
      quote.quoteId,
      executor: db,
    );
    expect(offers, hasLength(1));
    expect(offers.single.companyId, company.id);
    expect(offers.single.productId, product.id);
    expect(offers.single.finalPrice, 2400);

    await InsuranceQuoteService.acceptQuote(
      quoteId: quote.quoteId,
      itemId: quote.itemIds.single,
    );
    expect(
      (await db.rawQuery('SELECT COUNT(*) n FROM gl_entries')).single['n'],
      beforeGl,
      reason: 'accepting a quote must never post accounting',
    );

    final issued = await InsuranceQuoteService.issueAcceptedQuote(
      quoteId: quote.quoteId,
      policyNumber: 'POL-Q-0001',
      startDate: DateTime(2026, 9, 22),
      endDate: DateTime(2027, 9, 21),
      postingDate: DateTime(2026, 9, 22),
      createdBy: 'qa-owner',
    );

    expect(issued.pricing.grossProfit, 400);
    final quoteRow = (await db.query(
      'insurance_quotes',
      where: 'id=?',
      whereArgs: [quote.quoteId],
      limit: 1,
    ))
        .single;
    expect(quoteRow['status'], 'ISSUED');
    expect(quoteRow['issued_policy_id'], issued.policyId);

    final insuranceGl = await db.query(
      'gl_entries',
      where: 'source=? AND source_id=?',
      whereArgs: ['INSURANCE_POLICY', issued.policyId],
    );
    expect(insuranceGl, hasLength(1));

    final issuedBeforeTariffChange = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [issued.policyId],
      limit: 1,
    ))
        .single;
    await db.update(
      'insurance_products',
      {
        'default_commission_rate': 25.0,
        'updated_at': DateTime(2026, 10, 1).toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [product.id],
    );
    final issuedAfterTariffChange = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [issued.policyId],
      limit: 1,
    ))
        .single;

    expect(issuedAfterTariffChange['commission_rate'],
        issuedBeforeTariffChange['commission_rate']);
    expect(issuedAfterTariffChange['gross_profit'],
        issuedBeforeTariffChange['gross_profit']);
    expect(issuedAfterTariffChange['net_sale_amount'],
        issuedBeforeTariffChange['net_sale_amount']);
    expect(
      await db.query(
        'insurance_policy_versions',
        where: 'policy_id=?',
        whereArgs: [issued.policyId],
      ),
      hasLength(1),
      reason: 'master-data tariff changes must not rewrite issued snapshots',
    );

    final retried = await InsuranceQuoteService.issueAcceptedQuote(
      quoteId: quote.quoteId,
      policyNumber: 'POL-Q-0001',
      startDate: DateTime(2026, 9, 22),
      endDate: DateTime(2027, 9, 21),
      postingDate: DateTime(2026, 9, 22),
      createdBy: 'qa-owner',
    );
    expect(retried.wasExisting, isTrue);
    expect(retried.policyId, issued.policyId);
    expect(retried.glEntryId, issued.glEntryId);
    expect(retried.pricing.purchasePrice, issued.pricing.purchasePrice);
    expect(retried.pricing.salePrice, issued.pricing.salePrice);
    expect(retried.pricing.basePremium, issued.pricing.basePremium);
    expect(retried.pricing.commissionRate, issued.pricing.commissionRate);
    expect(retried.pricing.commissionAmount, issued.pricing.commissionAmount);
    expect(retried.pricing.grossProfit, issued.pricing.grossProfit);
    expect(retried.pricing.netSaleAmount, issued.pricing.netSaleAmount);
    expect(retried.pricing.netInsurerPayable, issued.pricing.netInsurerPayable);
    expect(retried.pricing.markupPercent, issued.pricing.markupPercent);
    expect(retried.pricing.marginPercent, issued.pricing.marginPercent);
    expect(
      await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['INSURANCE_POLICY', issued.policyId],
      ),
      hasLength(1),
      reason: 'an issued quote retry must never post a second GL entry',
    );

    await expectLater(
      InsuranceQuoteService.issueAcceptedQuote(
        quoteId: quote.quoteId,
        policyNumber: 'POL-Q-DIFFERENT',
        startDate: DateTime(2026, 9, 22),
        endDate: DateTime(2027, 9, 21),
        postingDate: DateTime(2026, 9, 22),
        createdBy: 'qa-owner',
      ),
      throwsStateError,
    );
  });
}
