import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/screens/insurance_contact_center_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_contact_center_service.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';

void main() {
  final prospect = InsuranceProspectRecord(
    id: 'PROSPECT-1',
    partyId: 'PARTY-1',
    name: 'عميل متابعة',
    phone: '0599000001',
    status: 'PROSPECT',
    createdAt: DateTime(2026, 9, 20),
    updatedAt: DateTime(2026, 9, 20),
  );

  InsuranceFollowUpTask task() => InsuranceFollowUpTask(
        id: 'FOLLOWUP:CONTACT:1',
        partyId: 'PARTY-1',
        partyName: null,
        policyId: null,
        taskType: 'CONTACT_FOLLOW_UP',
        dueAt: DateTime(2026, 9, 25, 10),
        status: 'OPEN',
        assignedTo: 'agent-1',
        notes: 'اتصال متابعة',
        createdAt: DateTime(2026, 9, 20),
        updatedAt: DateTime(2026, 9, 20),
      );

  test('contact center route is registered and open', () {
    expect(
      AppRoutes.registeredRoutes,
      contains(AppRoutes.insuranceAgentContactCenter),
    );
    expect(
      AppRoutes.isInsuranceAgentFrozenRoute(
        AppRoutes.insuranceAgentContactCenter,
      ),
      isFalse,
    );
  });

  testWidgets('contact center renders queue and completes task',
      (tester) async {
    var tasks = <InsuranceFollowUpTask>[task()];
    String? completedId;

    await tester.pumpWidget(
      MaterialApp(
        home: InsuranceContactCenterScreen(
          prospectsLoader: () async => [prospect],
          tasksLoader: () async => tasks,
          taskCompleter: (id) async {
            completedId = id;
            tasks = [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مركز التواصل'), findsOneWidget);
    expect(find.text('عميل متابعة'), findsOneWidget);
    expect(find.textContaining('اتصال متابعة'), findsOneWidget);
    expect(find.byKey(const Key('contactTask-FOLLOWUP:CONTACT:1')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const Key('completeContactTask-FOLLOWUP:CONTACT:1')),
    );
    await tester.pumpAndSettle();

    expect(completedId, 'FOLLOWUP:CONTACT:1');
    expect(find.text('لا توجد متابعات مفتوحة.'), findsOneWidget);
  });

  testWidgets('contact dialog records canonical party contact', (tester) async {
    String? recordedParty;
    String? recordedChannel;
    String? recordedResult;
    String? recordedNotes;

    await tester.pumpWidget(
      MaterialApp(
        home: InsuranceContactCenterScreen(
          prospectsLoader: () async => [prospect],
          tasksLoader: () async => const [],
          recorder: ({
            required operationId,
            required partyId,
            required channel,
            required result,
            required notes,
            required nextFollowUpAt,
          }) async {
            expect(operationId, startsWith('UI-'));
            recordedParty = partyId;
            recordedChannel = channel;
            recordedResult = result;
            recordedNotes = notes;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contactCenterAddContact')));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل تواصل جديد'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('contactCenterNotes')),
      'يرغب بعرض شامل',
    );
    await tester.tap(find.byKey(const Key('contactCenterSaveContact')));
    await tester.pumpAndSettle();

    expect(recordedParty, 'PARTY-1');
    expect(recordedChannel, 'PHONE');
    expect(recordedResult, 'CONTACTED');
    expect(recordedNotes, 'يرغب بعرض شامل');
  });
}
