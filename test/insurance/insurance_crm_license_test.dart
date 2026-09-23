import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/alerts/services/insurance_alert_center_service.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_crm_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/crm.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('prospect CRUD persists in Party Master and insurance_prospects',
      () async {
    final created = await InsuranceCrmService.createProspect(
      name: 'عميل مستهدف',
      phone: '0599000111',
      vehicleSummary: 'Hyundai Elantra',
      currentPolicyExpiry: DateTime(2026, 12, 31),
    );

    expect(created.name, 'عميل مستهدف');
    expect(created.vehicleSummary, 'Hyundai Elantra');

    final roles = await db.query(
      'party_roles',
      where: 'party_id=? AND role=?',
      whereArgs: [created.partyId, 'PROSPECT'],
    );
    expect(roles, hasLength(1));

    await InsuranceCrmService.updateProspect(
      id: created.id,
      name: 'عميل مستهدف محدث',
      phone: '0599000111',
      vehicleSummary: 'Kia K5',
      currentPolicyExpiry: DateTime(2027, 1, 15),
    );

    final updated = (await InsuranceCrmService.listProspects())
        .firstWhere((row) => row.id == created.id);
    expect(updated.name, 'عميل مستهدف محدث');
    expect(updated.vehicleSummary, 'Kia K5');
    expect(updated.currentPolicyExpiry, DateTime(2027, 1, 15));

    await InsuranceCrmService.archiveProspect(created.id);
    expect(
      (await InsuranceCrmService.listProspects())
          .where((row) => row.id == created.id),
      isEmpty,
    );
  });

  test('prospect converts to CUSTOMER + INSURED on same canonical party',
      () async {
    final prospect = await InsuranceCrmService.createProspect(
      name: 'مؤمن محتمل',
      phone: '0599000222',
    );

    final clientId = await InsuranceCrmService.convertToInsured(prospect.id);
    expect(clientId, greaterThan(0));

    final roles = await db.query(
      'party_roles',
      columns: const ['role', 'legacy_id'],
      where: 'party_id=?',
      whereArgs: [prospect.partyId],
      orderBy: 'role',
    );
    final roleNames = roles.map((row) => row['role']).toSet();
    expect(roleNames, containsAll(['PROSPECT', 'CUSTOMER', 'INSURED']));

    final customer = roles.firstWhere((row) => row['role'] == 'CUSTOMER');
    expect(customer['legacy_id'].toString(), clientId.toString());

    final duplicateParty = await db.query(
      'parties',
      where: 'id=?',
      whereArgs: ['CUSTOMER:$clientId'],
    );
    expect(duplicateParty, isEmpty);

    final prospectRow = (await db.query(
      'insurance_prospects',
      where: 'id=?',
      whereArgs: [prospect.id],
      limit: 1,
    ))
        .single;
    expect(prospectRow['status'], 'CONVERTED');
  });

  test(
    'insured resolver reuses formatted Arabic-digit phone and canonicalizes both records',
    () async {
      final first = await InsuranceCrmService.ensureInsuredCustomer(
        name: 'Canonical Insured',
        phone: '\u0660\u0665\u0669\u0668-\u0661\u0662\u0663 \u0664\u0665\u0666',
      );

      var party = (await db.query(
        'parties',
        columns: const ['phone'],
        where: 'id=?',
        whereArgs: [first.partyId],
      ))
          .single;
      var client = (await db.query(
        'clients',
        columns: const ['phone'],
        where: 'id=?',
        whereArgs: [first.clientId],
      ))
          .single;
      expect(party['phone'], '0598123456');
      expect(client['phone'], '0598123456');

      await db.update(
        'parties',
        {'phone': null},
        where: 'id=?',
        whereArgs: [first.partyId],
      );
      await db.update(
        'clients',
        {
          'phone':
              '\u06F0\u06F5\u06F9\u06F8 \u06F1\u06F2\u06F3-\u06F4\u06F5\u06F6',
        },
        where: 'id=?',
        whereArgs: [first.clientId],
      );

      final retried = await InsuranceCrmService.ensureInsuredCustomer(
        name: '  canonical   insured  ',
        phone: '(0598) 123-456',
      );
      expect(retried.partyId, first.partyId);
      expect(retried.clientId, first.clientId);

      party = (await db.query(
        'parties',
        columns: const ['phone'],
        where: 'id=?',
        whereArgs: [first.partyId],
      ))
          .single;
      client = (await db.query(
        'clients',
        columns: const ['phone'],
        where: 'id=?',
        whereArgs: [first.clientId],
      ))
          .single;
      expect(party['phone'], '0598123456');
      expect(client['phone'], '0598123456');
      expect(
        await db.query(
          'party_roles',
          where: 'party_id=? AND role=?',
          whereArgs: [first.partyId, 'CUSTOMER'],
        ),
        hasLength(1),
      );
    },
  );

  test('insured resolver rejects ambiguous normalized phone identities',
      () async {
    final first = await InsuranceCrmService.ensureInsuredCustomer(
      name: 'Correct Insured',
      phone: '0598-222-333',
    );
    final now = DateTime.now().toIso8601String();
    await db.insert('parties', {
      'id': 'AMBIGUOUS-PARTY',
      'display_name': 'Different Person',
      'phone': '(0598) 222333',
      'role_codes': '[]',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });

    await expectLater(
      InsuranceCrmService.ensureInsuredCustomer(
        name: 'Correct Insured',
        phone: '0598222333',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Multiple Party identities'),
        ),
      ),
    );
    expect(
      await db.query(
        'party_roles',
        where: 'party_id=? AND role=?',
        whereArgs: [first.partyId, 'CUSTOMER'],
      ),
      hasLength(1),
    );
  });

  test('insured resolver rejects a different name for one phone identity',
      () async {
    final first = await InsuranceCrmService.ensureInsuredCustomer(
      name: 'Original Insured',
      phone: '0598444555',
    );

    await expectLater(
      InsuranceCrmService.ensureInsuredCustomer(
        name: 'Another Insured',
        phone: '0598 444 555',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('different insured'),
        ),
      ),
    );

    expect(
      await db.query('clients', where: 'id=?', whereArgs: [first.clientId]),
      hasLength(1),
    );
    expect(
      (await db.rawQuery('SELECT COUNT(*) AS n FROM clients')).single['n'],
      1,
    );
  });

  test('driving license produces independent 60/30/14/7/3/1/0 alerts',
      () async {
    final prospect = await InsuranceCrmService.createProspect(
      name: 'صاحب رخصة',
      phone: '0599000333',
    );

    await InsuranceCrmService.upsertDrivingLicense(
      partyId: prospect.partyId,
      licenseNumber: 'DL-100',
      licenseType: 'خصوصي',
      issueDate: DateTime(2024, 1, 1),
      expiryDate: DateTime(2027, 1, 1),
      categories: const ['B'],
    );

    final license = (await db.query(
      'insurance_driver_licenses',
      where: 'party_id=?',
      whereArgs: [prospect.partyId],
      limit: 1,
    ))
        .single;
    expect(license['license_number'], 'DL-100');
    expect(license['categories_json'], '["B"]');

    final alerts = await db.query(
      'insurance_alerts',
      where: 'party_id=? AND alert_type=?',
      whereArgs: [prospect.partyId, 'DRIVING_LICENSE_EXPIRY'],
      orderBy: 'due_at',
    );
    expect(alerts, hasLength(7));
    expect(
      alerts.every((row) => row['policy_id'] == null),
      isTrue,
      reason: 'driving license alerts must stay separate from policy expiry',
    );

    final records = await InsuranceCrmService.listDrivingLicenses(
      partyId: prospect.partyId,
      executor: db,
    );
    expect(records, hasLength(1));
    expect(records.single.licenseNumber, 'DL-100');
    expect(records.single.licenseType, 'خصوصي');
    expect(records.single.issueDate, DateTime(2024, 1, 1));
    expect(records.single.expiryDate, DateTime(2027, 1, 1));
    expect(records.single.categories, ['B']);
  });

  test('CRM follow-up history updates prospect and feeds alert center',
      () async {
    final prospect = await InsuranceCrmService.createProspect(
      name: 'عميل متابعة',
      phone: '٠٥٩٩-١٢٣-٤٥٦',
      city: 'Bethlehem',
      source: 'Referral',
      currentCompany: 'Existing Insurer',
      status: 'PROSPECT',
    );
    expect(prospect.phone, '0599123456');
    expect(prospect.city, 'Bethlehem');
    expect(prospect.source, 'Referral');
    expect(prospect.currentCompany, 'Existing Insurer');

    final contactedAt = DateTime(2026, 9, 23, 9, 30);
    final nextFollowUp = DateTime(2026, 9, 26);
    await InsuranceCrmService.recordContact(
      prospectId: prospect.id,
      channel: 'WHATSAPP',
      contactAt: contactedAt,
      status: 'FOLLOW_UP',
      result: 'طلب عرض سعر',
      notes: 'إعادة التواصل بعد ثلاثة أيام',
      nextFollowUpAt: nextFollowUp,
      database: db,
    );

    final updated = (await InsuranceCrmService.listProspects(executor: db))
        .singleWhere((row) => row.id == prospect.id);
    expect(updated.status, 'FOLLOW_UP');
    expect(updated.lastContactAt, contactedAt);
    expect(updated.nextContactAt, nextFollowUp);
    expect(updated.contactResult, 'طلب عرض سعر');

    final history = await InsuranceCrmService.listContactHistory(
      prospectId: prospect.id,
      executor: db,
    );
    expect(history, hasLength(1));
    expect(history.single.channel, 'WHATSAPP');
    expect(history.single.result, 'طلب عرض سعر');
    expect(history.single.nextFollowUpAt, nextFollowUp);

    final alerts = await InsuranceAlertCenterService.listAlerts(
      asOf: DateTime(2026, 9, 23),
      window: InsuranceAlertWindow.next7,
      executor: db,
    );
    expect(
      alerts.where(
        (item) =>
            item.type == 'CUSTOMER_FOLLOW_UP' &&
            item.sourceId == prospect.id &&
            item.dueAt == nextFollowUp,
      ),
      hasLength(1),
    );
  });

  test('converted CRM edits keep Party and Customer identity synchronized',
      () async {
    final prospect = await InsuranceCrmService.createProspect(
      name: 'Converted CRM',
      phone: '0598777201',
    );
    final clientId = await InsuranceCrmService.convertToInsured(prospect.id);

    await InsuranceCrmService.updateProspect(
      id: prospect.id,
      name: 'Converted CRM Updated',
      phone: '٠٥٩٨-٧٧٧-٢٠٢',
      status: 'CONVERTED',
    );

    final party = (await db.query(
      'parties',
      columns: const ['display_name', 'phone'],
      where: 'id=?',
      whereArgs: [prospect.partyId],
      limit: 1,
    ))
        .single;
    final client = (await db.query(
      'clients',
      columns: const ['name', 'phone'],
      where: 'id=?',
      whereArgs: [clientId],
      limit: 1,
    ))
        .single;
    expect(party['display_name'], 'Converted CRM Updated');
    expect(party['phone'], '0598777202');
    expect(client['name'], 'Converted CRM Updated');
    expect(client['phone'], '0598777202');

    final resolved = await InsuranceCrmService.ensureInsuredCustomer(
      name: 'Converted CRM Updated',
      phone: '(0598) 777-202',
      executor: db,
    );
    expect(resolved.partyId, prospect.partyId);
    expect(resolved.clientId, clientId);
  });

  test('CRM create and update share canonical phone identity guards', () async {
    final first = await InsuranceCrmService.createProspect(
      name: 'CRM Canonical',
      phone: '٠٥٩٨-٧٧٧-١٠١',
    );
    expect(first.phone, '0598777101');

    await expectLater(
      InsuranceCrmService.createProspect(
        name: 'Different CRM Person',
        phone: '(0598) 777 101',
      ),
      throwsStateError,
    );

    final second = await InsuranceCrmService.createProspect(
      name: 'Second CRM Person',
      phone: '0598777102',
    );
    await expectLater(
      InsuranceCrmService.updateProspect(
        id: second.id,
        name: second.name,
        phone: '٠٥٩٨ ٧٧٧ ١٠١',
      ),
      throwsStateError,
    );

    final stored = (await InsuranceCrmService.listProspects(executor: db))
        .singleWhere((row) => row.id == second.id);
    expect(stored.phone, '0598777102');
  });
}
