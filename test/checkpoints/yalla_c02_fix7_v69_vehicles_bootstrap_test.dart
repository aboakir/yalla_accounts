import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('C02 FIX7 bootstraps vehicles for an existing v69 database', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE repairs(
        id TEXT PRIMARY KEY,
        vehicleNumber TEXT,
        vehicleType TEXT,
        vehicleModel TEXT,
        client_id INTEGER,
        receivedDate TEXT,
        created_at TEXT
      )
    ''');

    await db.insert('clients', {'id': 7, 'name': 'Legacy client'});
    await db.insert('repairs', {
      'id': 'r-legacy',
      'vehicleNumber': '12-345-67',
      'vehicleType': 'Tucson',
      'vehicleModel': '2019',
      'client_id': 7,
      'receivedDate': '2026-08-01T10:00:00.000Z',
      'created_at': '2026-08-01T10:00:00.000Z',
    });

    await DatabaseMigration.ensureP05VehicleCompatibilityBeforeValidation(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='vehicles'",
    );
    expect(tables, hasLength(1));

    final vehicles = await db.query('vehicles');
    expect(vehicles, hasLength(1));
    expect(vehicles.single['normalized_number'], '1234567');
    expect(vehicles.single['number'], '12-345-67');
    expect(vehicles.single['client_id'], 7);
  });

  test('C02 FIX7 never fabricates missing legacy prerequisites', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('CREATE TABLE clients(id INTEGER PRIMARY KEY)');

    await DatabaseMigration.ensureP05VehicleCompatibilityBeforeValidation(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='vehicles'",
    );
    expect(tables, isEmpty);
  });

  test('C02 FIX7 runs P05 compatibility before fail-closed validation', () {
    final source = File(
      'lib/core/services/db/database_migration.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('await ensureP05VehicleCompatibilityBeforeValidation(db);'),
    );
    expect(source, contains('if (oldV < 70) await _upgradeV70(db);'));
    expect(source, contains('await _validateDatabase(db);'));
    final constants = File(
      'lib/core/services/db/database_constants.dart',
    ).readAsStringSync();

    expect(constants, contains('static const int dbVersion = 76;'));
  });
}
