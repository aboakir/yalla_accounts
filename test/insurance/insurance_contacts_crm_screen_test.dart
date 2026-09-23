import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/screens/insurance_contacts_list_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CRM mobile screen exposes operational follow-up controls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final prospect = InsuranceProspectRecord(
      id: 'crm-ui-1',
      partyId: 'party-crm-ui-1',
      name: 'عميل شاشة CRM',
      phone: '0599555123',
      status: 'FOLLOW_UP',
      city: 'Bethlehem',
      source: 'Referral',
      currentCompany: 'Legacy Insurance',
      vehicleSummary: 'Kia Sportage',
      currentPolicyExpiry: DateTime(now.year, now.month + 1, 0),
      lastContactAt: now.subtract(const Duration(days: 1)),
      nextContactAt: now.add(const Duration(days: 2)),
      contactResult: 'مهتم',
      notes: 'ملاحظة CRM',
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: InsuranceContactsListScreen(
            loader: () async => [prospect],
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const Key('insuranceCrmScreen')), findsOneWidget);
    expect(find.text('عميل شاشة CRM'), findsOneWidget);
    expect(find.text('Bethlehem'), findsOneWidget);
    expect(find.text('Legacy Insurance'), findsOneWidget);
    expect(find.text('مهتم'), findsOneWidget);
    expect(find.byKey(const Key('insuranceCrmStatusFilter')), findsOneWidget);
    expect(find.byKey(const Key('insuranceCrmSearch')), findsOneWidget);
    expect(find.byKey(const Key('crmFollowUp-crm-ui-1')), findsOneWidget);
    expect(find.byKey(const Key('crmLicense-crm-ui-1')), findsOneWidget);

    final followUpButton = find.byKey(const Key('crmFollowUp-crm-ui-1'));
    final cardScrollable = find.ancestor(
      of: followUpButton,
      matching: find.byType(Scrollable),
    );
    expect(cardScrollable, findsWidgets);
    await tester.scrollUntilVisible(
      followUpButton,
      240,
      scrollable: cardScrollable.first,
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(followUpButton);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const Key('crmFollowUpStatus')), findsOneWidget);
    expect(find.byKey(const Key('crmFollowUpChannel')), findsOneWidget);
    expect(find.byKey(const Key('crmFollowUpResult')), findsOneWidget);
    expect(find.byKey(const Key('crmFollowUpNotes')), findsOneWidget);
    expect(find.byKey(const Key('crmFollowUpDate')), findsOneWidget);
    expect(find.byKey(const Key('crmFollowUpSave')), findsOneWidget);

    await tester.tap(find.text('إلغاء').last);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.enterText(
      find.byKey(const Key('insuranceCrmSearch')),
      'Legacy',
    );
    await tester.pump();
    expect(find.text('عميل شاشة CRM'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
