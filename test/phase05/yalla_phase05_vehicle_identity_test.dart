import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
      'P05 vehicle backfill deduplicates normalized numbers without deleting repairs',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        account_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE repairs(
        id TEXT PRIMARY KEY,
        vehicleModel TEXT,
        vehicleType TEXT,
        vehicleNumber TEXT,
        receivedDate TEXT,
        client_id INTEGER,
        created_at TEXT
      )
    ''');

    final clientId = await db.insert('clients', {
      'name': 'خالد أبو لبن',
      'type': 'أفراد',
    });

    await db.insert('repairs', {
      'id': 'r1',
      'vehicleModel': '2019',
      'vehicleType': 'توسان',
      'vehicleNumber': '12-345-67',
      'receivedDate': '2026-01-01T00:00:00.000Z',
      'client_id': clientId,
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    await db.insert('repairs', {
      'id': 'r2',
      'vehicleModel': '2020',
      'vehicleType': 'توسان',
      'vehicleNumber': '١٢ ٣٤٥ ٦٧',
      'receivedDate': '2026-02-01T00:00:00.000Z',
      'client_id': clientId,
      'created_at': '2026-02-01T00:00:00.000Z',
    });

    await VehicleTables.ensure(db);

    final vehicles = await db.query('vehicles');
    expect(vehicles, hasLength(1));
    expect(vehicles.single['normalized_number'], '1234567');
    expect(vehicles.single['model'], '2020');

    final repairs = await db.query('repairs');
    expect(repairs, hasLength(2));
  });

  test('P05 vehicle duplicate check uses normalized number', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE repairs(
        id TEXT PRIMARY KEY,
        vehicleNumber TEXT,
        vehicleType TEXT,
        vehicleModel TEXT,
        receivedDate TEXT,
        client_id INTEGER,
        created_at TEXT
      )
    ''');
    await VehicleTables.ensure(db);

    await db.insert('vehicles', {
      'normalized_number': VehicleTables.normalizeNumber('123-45'),
      'number': '123-45',
      'type': 'توسان',
      'model': '2020',
      'created_at': '2026-09-02T00:00:00.000Z',
      'updated_at': '2026-09-02T00:00:00.000Z',
    });

    final duplicate = await VehicleService.findDuplicateIdOn(db, '١٢٣ ٤٥');
    expect(duplicate, isNotNull);
  });

  test('P05 client duplicate lookup can exclude the edited row', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        account_id INTEGER
      )
    ''');

    final id = await db.insert('clients', {
      'name': 'أحمد محمد',
      'type': 'أفراد',
    });

    expect(
      await ClientService.findDuplicateIdOn(
        db,
        ' أحمد   محمد ',
        type: 'أفراد',
      ),
      id,
    );

    expect(
      await ClientService.findDuplicateIdOn(
        db,
        ' أحمد   محمد ',
        type: 'أفراد',
        excludeId: id,
      ),
      isNull,
    );
  });
}
