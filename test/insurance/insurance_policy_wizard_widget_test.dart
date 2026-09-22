import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/policy_wizard.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/steps/step_company_dates.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/steps/step_pricing_payment.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/steps/step_review_submit.dart';

void main() {
  Widget testHost(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  testWidgets('policy wizard applies Arabic right-to-left direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PolicyWizard())),
    );

    final pageView = find.byType(PageView);
    expect(pageView, findsOneWidget);
    expect(
      Directionality.of(tester.element(pageView)),
      TextDirection.rtl,
    );
  });

  testWidgets('company step requires the insurer policy number', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    final draft = PolicyDraft()
      ..companyName = 'شركة الأمان للتأمين'
      ..startDate = DateTime(2026, 9, 22)
      ..endDate = DateTime(2027, 9, 22);

    await tester.pumpWidget(
      testHost(StepCompanyDates(formKey: formKey, draft: draft)),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('رقم بوليصة شركة التأمين مطلوب'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'رقم بوليصة شركة التأمين'),
      'INS-2026-001',
    );
    expect(formKey.currentState!.validate(), isTrue);
    expect(draft.policyNumber, 'INS-2026-001');
  });

  testWidgets('cheque plan requires both issue date and due date', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    final cheque = PolicyChequeItem()
      ..amount = 1000
      ..bankName = 'بنك فلسطين'
      ..drawerName = 'أحمد علي'
      ..chequeNumber = 'CHQ-001';
    final draft = PolicyDraft()
      ..buyPrice = 800
      ..sellPrice = 1000;
    draft.payment.type = PolicyPaymentPlanType.chequesOnly;
    draft.payment.cheques.add(cheque);

    await tester.pumpWidget(
      testHost(StepPricingPayment(formKey: formKey, draft: draft)),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('تاريخ إصدار الشيك مطلوب'), findsOneWidget);

    cheque.issueDate = DateTime(2026, 9, 22);
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('تاريخ إصدار الشيك مطلوب'), findsNothing);
    expect(find.text('تاريخ استحقاق الشيك مطلوب'), findsOneWidget);

    cheque.dueDate = DateTime(2026, 10, 22);
    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('تاريخ استحقاق الشيك مطلوب'), findsNothing);
  });

  testWidgets('review shows purchase, sale, gross profit, and margin', (
    tester,
  ) async {
    final draft = PolicyDraft()
      ..buyPrice = 800
      ..sellPrice = 1000;

    await tester.pumpWidget(
      testHost(
        StepReviewSubmit(
          draft: draft,
          busy: false,
          onSave: () async {},
          onSaved: () {},
        ),
      ),
    );

    expect(find.text('سعر الشراء: 800.00'), findsOneWidget);
    expect(find.text('سعر البيع: 1000.00'), findsNWidgets(2));
    expect(find.text('إجمالي الربح: 200.00'), findsOneWidget);
    expect(find.text('هامش الربح: 20.00%'), findsOneWidget);
  });
}
