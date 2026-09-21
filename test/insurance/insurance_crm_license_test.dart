import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
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

  test('prospect CRUD persists in Party Master and insurance_prospects', () async {
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

  test('prospect converts to CUSTOMER + INSURED on same canonical party', () async {
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

  test('driving license produces independent 60/30/14/7/3/1/0 alerts', () async {
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
  });
}
