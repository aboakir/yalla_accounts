import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_contact_center_service.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_contact_center_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/contact-center.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('contact activity updates prospect and creates one follow-up task',
      () async {
    final prospect = await InsuranceCrmService.createProspect(
      name: 'Contact Center Prospect',
      phone: '0599777001',
    );
    final contactAt = DateTime(2026, 9, 23, 9, 30);
    final followUpAt = DateTime(2026, 9, 25, 11);

    final activity = await InsuranceContactCenterService.recordContact(
      operationId: 'CALL-001',
      partyId: prospect.partyId,
      channel: 'phone',
      contactAt: contactAt,
      result: 'INTERESTED',
      notes: 'Asked for comprehensive quote',
      nextFollowUpAt: followUpAt,
      createdBy: 'insurance-owner',
      assignedTo: 'agent-1',
      database: db,
    );

    expect(activity.id, 'CONTACT:CALL-001');
    expect(activity.channel, 'PHONE');
    expect(activity.nextFollowUpAt, followUpAt);

    final prospectRow = (await db.query(
      'insurance_prospects',
      where: 'id=?',
      whereArgs: [prospect.id],
      limit: 1,
    ))
        .single;
    expect(prospectRow['contact_result'], 'INTERESTED');
    expect(prospectRow['last_contact_at'], contactAt.toIso8601String());
    expect(prospectRow['next_contact_at'], followUpAt.toIso8601String());

    final contacts = await db.query(
      'insurance_contacts',
      where: 'party_id=?',
      whereArgs: [prospect.partyId],
    );
    expect(contacts, hasLength(1));

    final tasks = await db.query(
      'insurance_tasks',
      where: 'party_id=?',
      whereArgs: [prospect.partyId],
    );
    expect(tasks, hasLength(1));
    expect(tasks.single['id'], 'FOLLOWUP:CONTACT:CALL-001');
    expect(tasks.single['status'], 'OPEN');
    expect(tasks.single['assigned_to'], 'agent-1');
    expect(tasks.single['due_at'], followUpAt.toIso8601String());
  });

  test(
      'contact operation retry is idempotent but material mutation is rejected',
      () async {
    final prospect = await InsuranceCrmService.createProspect(
      name: 'Idempotent Prospect',
      phone: '0599777002',
    );
    final contactAt = DateTime(2026, 9, 23, 10);
    final followUpAt = DateTime(2026, 9, 24, 10);

    Future<InsuranceContactActivity> write(String notes) =>
        InsuranceContactCenterService.recordContact(
          operationId: 'CALL-IDEMPOTENT',
          partyId: prospect.partyId,
          channel: 'WHATSAPP',
          contactAt: contactAt,
          result: 'QUOTE_REQUESTED',
          notes: notes,
          nextFollowUpAt: followUpAt,
          createdBy: 'agent-2',
          assignedTo: 'agent-2',
          database: db,
        );

    final first = await write('Send quote tomorrow');
    final retried = await write('Send quote tomorrow');
    expect(retried.id, first.id);
    expect(
      await db.query(
        'insurance_contacts',
        where: 'id=?',
        whereArgs: [first.id],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'insurance_tasks',
        where: 'id=?',
        whereArgs: ['FOLLOWUP:${first.id}'],
      ),
      hasLength(1),
    );

    await expectLater(
      write('Changed material note'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('different material fields'),
        ),
      ),
    );
  });

  test('timeline is newest first and due task queue completes idempotently',
      () async {
    final prospect = await InsuranceCrmService.createProspect(
      name: 'Timeline Prospect',
      phone: '0599777003',
    );
    await InsuranceContactCenterService.recordContact(
      operationId: 'TIMELINE-OLD',
      partyId: prospect.partyId,
      channel: 'PHONE',
      contactAt: DateTime(2026, 9, 20, 9),
      result: 'NO_ANSWER',
      nextFollowUpAt: DateTime(2026, 9, 22, 9),
      assignedTo: 'agent-3',
      database: db,
    );
    await InsuranceContactCenterService.recordContact(
      operationId: 'TIMELINE-NEW',
      partyId: prospect.partyId,
      channel: 'EMAIL',
      contactAt: DateTime(2026, 9, 23, 9),
      result: 'CONTACTED',
      nextFollowUpAt: DateTime(2026, 10, 1, 9),
      assignedTo: 'agent-3',
      database: db,
    );

    final timeline = await InsuranceContactCenterService.listTimeline(
      prospect.partyId,
      executor: db,
    );
    expect(timeline.map((row) => row.id).toList(), [
      'CONTACT:TIMELINE-NEW',
      'CONTACT:TIMELINE-OLD',
    ]);

    final due = await InsuranceContactCenterService.listTasks(
      through: DateTime(2026, 9, 23, 23, 59),
      assignedTo: 'agent-3',
      executor: db,
    );
    expect(due, hasLength(1));
    expect(due.single.id, 'FOLLOWUP:CONTACT:TIMELINE-OLD');

    final completed = await InsuranceContactCenterService.completeTask(
      due.single.id,
      completedAt: DateTime(2026, 9, 23, 12),
      database: db,
    );
    expect(completed.status, 'DONE');
    final retried = await InsuranceContactCenterService.completeTask(
      due.single.id,
      database: db,
    );
    expect(retried.status, 'DONE');

    expect(
      await InsuranceContactCenterService.listTasks(
        through: DateTime(2026, 9, 23, 23, 59),
        assignedTo: 'agent-3',
        executor: db,
      ),
      isEmpty,
    );
  });

  test('contact center rejects missing or inactive Party identity', () async {
    await expectLater(
      InsuranceContactCenterService.recordContact(
        operationId: 'MISSING-PARTY',
        partyId: 'NO-SUCH-PARTY',
        channel: 'PHONE',
        database: db,
      ),
      throwsStateError,
    );

    final prospect = await InsuranceCrmService.createProspect(
      name: 'Inactive Prospect',
      phone: '0599777004',
    );
    await db.update(
      'parties',
      {'is_active': 0},
      where: 'id=?',
      whereArgs: [prospect.partyId],
    );
    await expectLater(
      InsuranceContactCenterService.recordContact(
        operationId: 'INACTIVE-PARTY',
        partyId: prospect.partyId,
        channel: 'PHONE',
        database: db,
      ),
      throwsStateError,
    );
  });
}
