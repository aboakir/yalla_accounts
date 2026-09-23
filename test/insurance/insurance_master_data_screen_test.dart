import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/screens/insurance_master_data_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const companies = [
    InsuranceCompanyRecord(
      id: 1,
      partyId: 'party-1',
      supplierId: 10,
      code: 'A',
      name: 'Company A',
      defaultCommissionRate: 10,
      isActive: true,
      payable: 2000,
      paid: 500,
    ),
    InsuranceCompanyRecord(
      id: 2,
      partyId: 'party-2',
      supplierId: 20,
      code: 'B',
      name: 'Company B',
      defaultCommissionRate: 8,
      isActive: true,
    ),
  ];

  const products = {
    1: [
      InsuranceProductRecord(
        id: 'p-a',
        companyId: 1,
        code: 'COMP',
        name: 'Comprehensive',
        productType: 'MOTOR',
        defaultCommissionRate: 10,
        isActive: true,
      ),
    ],
    2: [
      InsuranceProductRecord(
        id: 'p-b',
        companyId: 2,
        code: 'TPL',
        name: 'Third Party',
        productType: 'MOTOR',
        defaultCommissionRate: 8,
        isActive: true,
      ),
    ],
  };

  const coverages = {
    'p-a': [
      InsuranceCoverageRecord(
        id: 'c-a',
        productId: 'p-a',
        code: 'OWN',
        name: 'Own Damage',
        deductible: 250,
        limitAmount: 10000,
        isActive: true,
      ),
    ],
    'p-b': [
      InsuranceCoverageRecord(
        id: 'c-b',
        productId: 'p-b',
        code: 'TPL',
        name: 'Third Party Liability',
        deductible: 0,
        isActive: true,
      ),
    ],
  };

  testWidgets(
      'master data screen cascades company product and coverage selection',
      (tester) async {
    final companyLoads = <int>[];
    final coverageLoads = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: InsuranceMasterDataScreen(
          companiesLoader: () async => companies,
          productsLoader: (companyId) async {
            companyLoads.add(companyId);
            return products[companyId] ?? const [];
          },
          coveragesLoader: (productId) async {
            coverageLoads.add(productId);
            return coverages[productId] ?? const [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insuranceMasterDataScreen')), findsOneWidget);
    expect(find.byKey(const Key('masterCompany-1')), findsOneWidget);
    expect(find.byKey(const Key('masterProduct-p-a')), findsOneWidget);
    expect(find.byKey(const Key('masterCoverage-c-a')), findsOneWidget);
    expect(companyLoads, [1]);
    expect(coverageLoads, ['p-a']);

    await tester.tap(find.byKey(const Key('masterCompany-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('masterProduct-p-b')), findsOneWidget);
    expect(find.byKey(const Key('masterCoverage-c-b')), findsOneWidget);
    expect(companyLoads, [1, 2]);
    expect(coverageLoads, ['p-a', 'p-b']);
  });

  test('master data route is registered and not frozen', () {
    expect(AppRoutes.isRegisteredRoute(AppRoutes.insuranceAgentMasterData),
        isTrue);
    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(
            AppRoutes.insuranceAgentMasterData),
        isFalse);
  });
}
