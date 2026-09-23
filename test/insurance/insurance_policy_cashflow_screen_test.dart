import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_policy_cashflow_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/screens/policy_payments_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('policy cashflow mobile screen exposes canonical actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime(2026, 9, 23);
    final snapshot = InsurancePolicyCashflowSnapshot(
      policyId: 'policy-ui-1',
      policyNumber: 'POL-UI-001',
      insuredName: 'Mobile Customer',
      companyName: 'Mobile Insurance',
      vehiclePlate: '30-123-45',
      balances: const InsurancePolicyBalances(
        sale: 2480,
        customerReceipts: 600,
        customerOutstanding: 1880,
        insurerPayable: 2000,
        insurerPayments: 500,
        insurerOutstanding: 1500,
      ),
      movements: [
        InsurancePolicyCashflowMovement(
          key: 'CUSTOMER_RECEIPT:77',
          direction: 'CUSTOMER_RECEIPT',
          amount: 600,
          status: 'POSTED',
          activityDate: now,
          method: 'CASH',
          receiptNumber: 77,
          notes: 'canonical receipt',
        ),
        InsurancePolicyCashflowMovement(
          key: 'INSURER_PAYMENT:v-1',
          direction: 'INSURER_PAYMENT',
          amount: 500,
          status: 'POSTED',
          activityDate: now,
          method: 'CASH',
          voucherId: 'v-1',
          notes: 'canonical voucher',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PolicyPaymentsScreen(
          policyId: 'policy-ui-1',
          loader: (_) async => snapshot,
          chequeBookLoader: () async => const [
            InsuranceChequeBookOption(
              id: 'book-ui-1',
              bankAccountId: 10,
              bookNumber: 'BOOK-UI',
              nextAvailableNumber: 100,
              lastChequeNumber: 120,
              bankAccountName: 'UI Bank',
              bankAccountCode: '1010',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('insurancePolicyCashflowScreen')), findsOneWidget);
    expect(find.textContaining('POL-UI-001'), findsWidgets);
    expect(find.text('1880.00'), findsOneWidget);
    expect(find.text('1500.00'), findsOneWidget);
    expect(find.byKey(const Key('insuranceCollectCustomer')), findsOneWidget);
    expect(find.byKey(const Key('insurancePayInsurer')), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('insuranceCollectCustomer')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('insuranceCustomerReceiptAmount')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('insuranceCustomerReceiptMethod')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('insuranceCustomerReceiptSave')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull,
        reason: 'customer receipt dialog must not overflow');
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();

    final payInsurer = find.byKey(const Key('insurancePayInsurer'));
    await tester.scrollUntilVisible(
      payInsurer,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'cashflow screen scroll must not overflow');
    await tester.tap(payInsurer);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('insuranceInsurerPaymentAmount')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('insuranceInsurerPaymentMethod')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('insuranceInsurerPaymentSave')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull,
        reason: 'insurer payment dialog must not overflow');

    await tester.tap(
      find.byKey(const Key('insuranceInsurerPaymentMethod')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('شيك صادر').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('insuranceInsurerChequeBook')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('insuranceInsurerChequeNextNumber')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('insuranceInsurerChequeDueDate')),
      findsOneWidget,
    );
    expect(find.textContaining('#100'), findsWidgets);
    expect(find.byKey(const Key('insuranceInsurerChequeNumber')), findsNothing);
    expect(tester.takeException(), isNull,
        reason: 'issued-cheque controls must not overflow');
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();

    final reverse = find.byKey(
      const Key('insuranceMovementReverse-CUSTOMER_RECEIPT:77'),
    );
    await tester.scrollUntilVisible(
      reverse,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(reverse);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('insuranceMovementReversalReason')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('insuranceMovementReverseConfirm')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull,
        reason: 'reversal dialog must not overflow');
  });
}
