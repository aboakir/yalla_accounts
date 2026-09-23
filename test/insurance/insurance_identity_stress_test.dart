import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

int _count(List<Map<String, Object?>> rows) =>
    (rows.single['n'] as num).toInt();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_identity_stress_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/identity.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
  });
  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('1000 normalized-phone identity conflicts never create duplicates',
      () async {
    final partiesBefore =
        _count(await db.rawQuery('SELECT COUNT(*) n FROM parties'));
    final clientsBefore =
        _count(await db.rawQuery('SELECT COUNT(*) n FROM clients'));
    final rolesBefore =
        _count(await db.rawQuery('SELECT COUNT(*) n FROM party_roles'));

    final owner = await InsuranceCrmService.ensureInsuredCustomer(
      name: 'Identity Owner',
      phone: '0598-000-001',
    );

    var rejected = 0;
    for (var index = 0; index < 1000; index++) {
      final phone = index.isEven ? '٠٥٩٨-٠٠٠-٠٠١' : '(0598) 000 001';
      try {
        await InsuranceCrmService.ensureInsuredCustomer(
          name: 'Conflicting Owner $index',
          phone: phone,
        );
        fail('conflict $index was accepted');
      } on StateError {
        rejected++;
      }
    }

    expect(rejected, 1000);
    expect(
      _count(await db.rawQuery('SELECT COUNT(*) n FROM parties')),
      partiesBefore + 1,
    );
    expect(
      _count(await db.rawQuery('SELECT COUNT(*) n FROM clients')),
      clientsBefore + 1,
    );
    expect(
      _count(await db.rawQuery('SELECT COUNT(*) n FROM party_roles')),
      rolesBefore + 3,
      reason: 'one prospect/customer/insured identity only',
    );

    expect(
      await db.query(
        'party_roles',
        where: 'party_id=? AND role=?',
        whereArgs: [owner.partyId, 'CUSTOMER'],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'party_roles',
        where: 'party_id=? AND role=?',
        whereArgs: [owner.partyId, 'INSURED'],
      ),
      hasLength(1),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('repair upsert cannot silently transfer a canonical vehicle owner',
      () async {
    final firstOwner = await InsuranceCrmService.ensureInsuredCustomer(
      name: 'Vehicle Owner One',
      phone: '0598111001',
    );
    final secondOwner = await InsuranceCrmService.ensureInsuredCustomer(
      name: 'Vehicle Owner Two',
      phone: '0598111002',
    );

    final vehicleId = await VehicleService.upsertFromRepairOn(
      db,
      number: '12-345-67',
      type: 'Toyota',
      model: '2024',
      clientId: firstOwner.clientId,
    );

    await expectLater(
      VehicleService.upsertFromRepairOn(
        db,
        number: '١٢ ٣٤٥ ٦٧',
        type: 'Toyota',
        model: '2025',
        clientId: secondOwner.clientId,
      ),
      throwsStateError,
    );
    final stored = (await db.query(
      'vehicles',
      where: 'id=?',
      whereArgs: [vehicleId],
      limit: 1,
    ))
        .single;
    expect(stored['client_id'], firstOwner.clientId);
    expect(stored['normalized_number'], '1234567');

    final replayId = await VehicleService.upsertFromRepairOn(
      db,
      number: '12 / 345 / 67',
      type: 'Toyota',
      model: '2025',
      clientId: firstOwner.clientId,
    );
    expect(replayId, vehicleId);
    expect(
      _count(await db.rawQuery(
        "SELECT COUNT(*) n FROM vehicles WHERE normalized_number='1234567'",
      )),
      1,
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
