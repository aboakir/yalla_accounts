import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v78 to v79 backfills stable vehicle owner without fake local sync',
      () async {
    final dir = await Directory.systemTemp.createTemp('phase07_v79_');
    final path = '${dir.path}/fixture.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(79));
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      final clientId = await db.insert('clients', {
        'name': 'Migration Vehicle Owner',
        'type': 'أفراد',
        'phone': '',
        'email': '',
        'address': '',
        'notes': '',
      });
      final partyRole = (await db.query(
        'party_roles',
        where: 'role=? AND legacy_id=?',
        whereArgs: ['CUSTOMER', clientId.toString()],
      ))
          .single;
      final partyRegistry = (await db.query(
        SyncFoundationTables.registry,
        columns: const ['entity_uuid'],
        where: 'entity_type=? AND local_id=?',
        whereArgs: ['party', partyRole['party_id']],
      ))
          .single;
      final partyUuid = partyRegistry['entity_uuid']!.toString();
      final now = DateTime.utc(2026, 9, 16, 10).toIso8601String();
      final vehicleId = await db.insert('vehicles', {
        'normalized_number': 'MIG7901',
        'number': 'MIG-79-01',
        'type': 'Migration',
        'model': '2026',
        'client_id': clientId,
        'owner_party_uuid': null,
        'is_active': 1,
        'notes': 'preserve me',
        'created_at': now,
        'updated_at': now,
      });
      final localBefore = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM ${SyncFoundationTables.changes} WHERE entity_type='vehicle' AND origin='local'",
      ))
          .single['c'];
      await db.delete('schema_migrations', where: 'version=?', whereArgs: [79]);
      for (final name in [
        'trg_sync_vehicles_insert',
        'trg_sync_vehicles_update',
        'trg_sync_vehicles_delete',
        'trg_sync_vehicles_pk_guard',
      ]) {
        await db.execute('DROP TRIGGER IF EXISTS $name');
      }
      await db.execute('DROP INDEX IF EXISTS idx_vehicles_owner_party_uuid');
      await db.execute('ALTER TABLE vehicles DROP COLUMN owner_party_uuid');
      await db.execute('ALTER TABLE vehicles DROP COLUMN is_active');
      await db.setVersion(78);
      await db.close();

      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      expect(
        await db
            .query('schema_migrations', where: 'version=?', whereArgs: [79]),
        hasLength(1),
      );
      final vehicle = (await db.query(
        'vehicles',
        where: 'id=?',
        whereArgs: [vehicleId],
      ))
          .single;
      expect(vehicle['number'], 'MIG-79-01');
      expect(vehicle['notes'], 'preserve me');
      expect(vehicle['is_active'], 1);
      expect(vehicle['owner_party_uuid'], partyUuid);
      final localAfter = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM ${SyncFoundationTables.changes} WHERE entity_type='vehicle' AND origin='local'",
      ))
          .single['c'];
      expect(localAfter, localBefore);
      final registry = (await db.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND local_id=?',
        whereArgs: ['vehicle', vehicleId.toString()],
      ))
          .single;
      expect(registry['revision'], 1);
      expect(registry['is_voided'], 0);
    } finally {
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });
}
