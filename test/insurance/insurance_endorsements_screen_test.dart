import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/screens/insurance_endorsements_screen.dart';

void main() {
  testWidgets('endorsement screen renders posted policy endorsement',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InsurancePolicyEndorsementsScreen(
          policyId: 'POL-1',
          loader: (_) async => <Map<String, Object?>>[
            {
              'id': 'END:1',
              'policy_id': 'POL-1',
              'endorsement_type': 'VEHICLE_CHANGE',
              'effective_date': '2026-09-22T00:00:00.000',
              'delta_sale': 100.0,
              'delta_cost': 70.0,
              'delta_tax': 0.0,
              'status': 'POSTED',
            },
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insurancePolicyEndorsementsScreen')),
        findsOneWidget);
    expect(find.text('VEHICLE_CHANGE'), findsOneWidget);
    expect(find.byKey(const Key('reverseEndorsement-END:1')), findsOneWidget);
    expect(find.byKey(const Key('addInsuranceEndorsement')), findsOneWidget);
  });

  testWidgets('endorsement screen shows empty state from injected loader',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InsurancePolicyEndorsementsScreen(
          policyId: 'POL-EMPTY',
          loader: (_) async => const <Map<String, Object?>>[],
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insurancePolicyEndorsementsScreen')),
        findsOneWidget);
    expect(find.byKey(const Key('addInsuranceEndorsement')), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
