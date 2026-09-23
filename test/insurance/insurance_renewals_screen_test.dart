import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/insurance_agent/renewals/screens/insurance_renewals_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/renewals/services/insurance_renewal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<InsuranceRenewalCandidate> rows() => [
        InsuranceRenewalCandidate(
          id: 'ren-1',
          policyId: 'policy-due',
          renewalDate: DateTime(2026, 10, 10),
          status: 'PENDING',
          daysRemaining: 18,
          policyNumber: 'POL-DUE-001',
          documentNumber: 'INS-0001',
          customerName: 'Customer Due',
        ),
        InsuranceRenewalCandidate(
          id: 'ren-2',
          policyId: 'policy-expired',
          renewalDate: DateTime(2026, 9, 1),
          status: 'CONTACTED',
          daysRemaining: -21,
          policyNumber: 'POL-OLD-001',
          documentNumber: 'INS-0002',
          customerName: 'Customer Expired',
        ),
        InsuranceRenewalCandidate(
          id: 'ren-3',
          policyId: 'policy-renewed',
          renewalDate: DateTime(2026, 9, 15),
          status: 'RENEWED',
          daysRemaining: -7,
          policyNumber: 'POL-NEW-001',
          documentNumber: 'INS-0003',
          customerName: 'Customer Renewed',
        ),
      ];

  Future<void> pumpScreen(
    WidgetTester tester, {
    InsuranceRenewalUpdater? updater,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InsuranceRenewalsScreen(
          loader: () async => rows(),
          updater: updater,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renewal center filters due, expired and renewed candidates',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('insuranceRenewalsScreen')), findsOneWidget);
    expect(find.byKey(const Key('renewalCard-policy-due')), findsOneWidget);
    expect(find.byKey(const Key('renewalCard-policy-expired')), findsOneWidget);
    expect(find.byKey(const Key('renewalCard-policy-renewed')), findsOneWidget);

    await tester.tap(find.byKey(const Key('renewalFilterDue30')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('renewalCard-policy-due')), findsOneWidget);
    expect(find.byKey(const Key('renewalCard-policy-expired')), findsNothing);
    expect(find.byKey(const Key('renewalCard-policy-renewed')), findsNothing);

    await tester.tap(find.byKey(const Key('renewalFilterExpired')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('renewalCard-policy-expired')), findsOneWidget);
    expect(find.byKey(const Key('renewalCard-policy-due')), findsNothing);

    await tester.tap(find.byKey(const Key('renewalFilterRenewed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('renewalCard-policy-renewed')), findsOneWidget);
    expect(find.byKey(const Key('renewalCard-policy-expired')), findsNothing);
  });

  testWidgets('status action persists through injected canonical updater',
      (tester) async {
    String? capturedPolicyId;
    String? capturedStatus;
    DateTime? contactedAt;

    await pumpScreen(
      tester,
      updater: ({
        required String policyId,
        required String status,
        DateTime? lastContactAt,
        DateTime? nextContactAt,
        String? outcome,
      }) async {
        capturedPolicyId = policyId;
        capturedStatus = status;
        contactedAt = lastContactAt;
      },
    );

    await tester.tap(find.byKey(const Key('renewalStatus-policy-due')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('renewalStatusOption-CONTACTED')), findsOneWidget);

    await tester.tap(find.byKey(const Key('renewalStatusOption-CONTACTED')));
    await tester.pumpAndSettle();

    expect(capturedPolicyId, 'policy-due');
    expect(capturedStatus, 'CONTACTED');
    expect(contactedAt, isNotNull);
  });
}
