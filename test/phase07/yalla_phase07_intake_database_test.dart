import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/repair_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair_intake_draft.dart';
import 'package:yalla_accounts/features/repairs/services/repair_intake_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('P07 migration adds intake columns without rebuilding repair rows',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE repairs(
        id TEXT PRIMARY KEY,
        vehicleNumber TEXT,
        fileValue REAL
      )
    ''');
    await db.insert('repairs', <String, Object?>{
      'id': 'legacy-repair',
      'vehicleNumber': '11-111-11',
      'fileValue': 777.0,
    });

    await RepairTables.ensureP07IntakeSchema(db);

    final info = await db.rawQuery('PRAGMA table_info(repairs)');
    final columns = info.map((row) => row['name']?.toString()).toSet();
    expect(
        columns,
        containsAll(<String>[
          'odometer',
          'fuel_level',
          'previous_damage',
          'customer_signature_path',
          'intake_completed_at',
        ]));

    final legacy = (await db.query(
      'repairs',
      where: 'id = ?',
      whereArgs: const <Object?>['legacy-repair'],
    ))
        .single;
    expect(legacy['vehicleNumber'], '11-111-11');
    expect(legacy['fileValue'], 777.0);
  });

  test('P07 save creates intake only and queues local-first repair mutation',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await ClientService.createTable(db);
    await RepairTables.createAllTables(db);
    await VehicleTables.ensure(db);
    await TechnicalTables.createAllTables(db);

    final repairId = await RepairIntakeService.saveOn(
      db,
      RepairIntakeDraft(
        clientName: 'عميل اختبار P07',
        clientType: 'أفراد',
        vehicleNumber: '99-777-22',
        vehicleType: 'توسان',
        vehicleModel: '2024',
        receivedDate: DateTime.utc(2026, 9, 2, 17, 30),
        odometer: 54321,
        fuelLevel: 50,
        previousDamage: 'خدش سابق في الباب الخلفي',
        photoPaths: const <String>['/tmp/p07-photo.jpg'],
        customerSignaturePath: '/tmp/p07-signature.png',
        notes: 'استلام تجريبي',
      ),
    );

    final repair = (await db.query(
      'repairs',
      where: 'id = ?',
      whereArgs: <Object?>[repairId],
    ))
        .single;

    expect(repair['status'], 'QUOTE');
    expect(repair['vehicleStatus'], 'بانتظار الإصلاح');
    expect(repair['odometer'], 54321);
    expect(repair['fuel_level'], 50);
    expect(repair['previous_damage'], 'خدش سابق في الباب الخلفي');
    expect(repair['customer_signature_path'], '/tmp/p07-signature.png');
    expect(repair['fileValue'], 0.0);
    expect(repair['isLedgerEnabled'], 0);
    expect((repair['invoiceNumber'] ?? '').toString(), isEmpty);

    final images = await db.query(
      'repairs_images',
      where: 'repair_id = ?',
      whereArgs: <Object?>[repairId],
    );
    expect(images, hasLength(1));
    expect(images.single['path'], '/tmp/p07-photo.jpg');

    final queued = (await db.query(
      TechnicalTables.outboxTable,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>['repair', repairId],
    ))
        .single;
    expect(queued['sent'], 0);
    final payload =
        jsonDecode(queued['payload_json'] as String) as Map<String, dynamic>;
    expect(payload['workflow_status'], 'QUOTE');
    expect(payload['intake_completed'], isTrue);
  });
}
