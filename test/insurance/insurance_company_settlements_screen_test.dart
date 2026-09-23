import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/screens/insurance_company_settlements_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_company_settlement_service.dart';

void main() {
  test('insurance settlements route is registered and open', () {
    expect(AppRoutes.isRegisteredRoute(AppRoutes.insuranceAgentSettlements),
        isTrue);
    expect(
      AppRoutes.isInsuranceAgentFrozenRoute(
          AppRoutes.insuranceAgentSettlements),
      isFalse,
    );
  });

  testWidgets('settlement screen loads companies and previews reconciliation',
      (tester) async {
    final snapshot = InsuranceCompanySettlementSnapshot(
      settlementId: null,
      companyId: 7,
      companyName: 'شركة الاختبار',
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      grossPolicies: 1000,
      cancellations: 100,
      commission: 120,
      previousPayments: 200,
      payable: 700,
      settlementPayments: 0,
      items: const [
        InsuranceSettlementItem(
          type: 'POLICY_ISSUE',
          sourceId: 'event-1',
          policyId: 'policy-1',
          label: 'POL-1',
          amount: 1000,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InsuranceCompanySettlementsScreen(
          companiesLoader: () async => const [
            InsuranceSettlementCompany(id: 7, name: 'شركة الاختبار'),
          ],
          recentLoader: () async => const [],
          previewer: ({
            required int companyId,
            required DateTime periodStart,
            required DateTime periodEnd,
          }) async {
            expect(companyId, 7);
            return snapshot;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تسويات شركات التأمين'), findsOneWidget);
    expect(find.text('شركة الاختبار'), findsOneWidget);
    expect(find.text('معاينة'), findsOneWidget);

    await tester.tap(find.text('معاينة'));
    await tester.pumpAndSettle();

    expect(find.text('إجمالي البوالص'), findsOneWidget);
    expect(find.text('1,000.00'), findsOneWidget);
    expect(find.text('المتبقي'), findsOneWidget);
    expect(find.text('700.00'), findsAtLeastNWidgets(1));
  });
}
