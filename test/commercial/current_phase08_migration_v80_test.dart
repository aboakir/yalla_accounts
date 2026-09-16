import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v79 to v80 backfills Repair stable references without fake sync',
      () async {
    final dir = await Directory.systemTemp.createTemp('phase08_v80_');
    final path = '${dir.path}/fixture.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(80));
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      final clientId = await db.insert('clients', {
        'name': 'Migration Repair Owner',
        'type': 'أفراد',
        'phone': '',
        'email': '',
        'address': '',
        'notes': '',
      });
      final partyId = await PartyTables.resolvePartyId(
        db,
        role: 'CUSTOMER',
        legacyId: clientId,
      );
      expect(partyId, isNotNull);
      final partyIdentity = (await db.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND local_id=?',
        whereArgs: ['party', partyId],
      ))
          .single;
      final partyUuid = partyIdentity['entity_uuid']!.toString();

      final now = DateTime.utc(2026, 9, 16, 18).toIso8601String();
      final vehicleId = await db.insert('vehicles', {
        'normalized_number': VehicleTables.normalizeNumber('12-345-67'),
        'number': '12-345-67',
        'type': 'Test',
        'model': '2026',
        'client_id': clientId,
        'owner_party_uuid': partyUuid,
        'is_active': 1,
        'notes': '',
        'created_at': now,
        'updated_at': now,
      });
      final vehicleIdentity = (await db.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND local_id=?',
        whereArgs: ['vehicle', vehicleId.toString()],
      ))
          .single;
      final vehicleUuid = vehicleIdentity['entity_uuid']!.toString();
      const repairId = 'phase08-migration-repair';
      await db.insert('repairs', {
        'id': repairId,
        'vehicleModel': '2026',
        'vehicleType': 'Test',
        'vehicleNumber': '12-345-67',
        'beneficiaryType': 'أفراد',
        'beneficiaryName': 'Migration Repair Owner',
        'client_id': clientId,
        'customer_party_uuid': partyUuid,
        'vehicle_entity_uuid': vehicleUuid,
        'is_active': 1,
        'status': 'QUOTE',
        'fileValue': 1234.0,
        'paidAmount': 400.0,
        'imagePaths': '["local-only.jpg"]',
        'created_at': now,
        'updated_at': now,
      });
      final localBefore = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM ${SyncFoundationTables.changes} WHERE origin='local'",
      ))
          .single['c'] as int;

      await db.execute('DROP TRIGGER IF EXISTS trg_sync_v3_change_to_outbox');
      await db
          .execute('DROP TRIGGER IF EXISTS trg_sync_v3_outbox_identity_guard');
      for (final op in ['insert', 'update', 'delete']) {
        await db.execute('DROP TRIGGER IF EXISTS trg_sync_repairs_$op');
      }
      await db.rawUpdate('''UPDATE ${UnifiedSyncTables.outbox}
        SET payload_json=json_remove(payload_json,
          '\$.customer_party_uuid','\$.vehicle_entity_uuid')
        WHERE entity_type='repair' AND entity_id=?''', [repairId]);
      for (final column in [
        'customer_party_uuid',
        'vehicle_entity_uuid',
        'is_active',
      ]) {
        await db.execute('ALTER TABLE repairs DROP COLUMN $column');
      }
      await db.delete('schema_migrations', where: 'version=?', whereArgs: [80]);
      await db.setVersion(79);
      await db.close();

      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      expect(
        await db
            .query('schema_migrations', where: 'version=?', whereArgs: [80]),
        hasLength(1),
      );
      final repair = (await db.query(
        'repairs',
        where: 'id=?',
        whereArgs: [repairId],
      ))
          .single;
      expect(repair['customer_party_uuid'], partyUuid);
      expect(repair['vehicle_entity_uuid'], vehicleUuid);
      expect(repair['is_active'], 1);

      final payloadRow = (await db.query(
        UnifiedSyncTables.outbox,
        columns: ['payload_json'],
        where: "entity_type='repair' AND entity_id=?",
        whereArgs: [repairId],
        orderBy: 'created_at DESC',
        limit: 1,
      ))
          .single;
      final payload = Map<String, dynamic>.from(
        jsonDecode(payloadRow['payload_json']!.toString()) as Map,
      );
      expect(payload['customer_party_uuid'], partyUuid);
      expect(payload['vehicle_entity_uuid'], vehicleUuid);
      expect(payload.containsKey('client_id'), isFalse);
      expect(payload.containsKey('fileValue'), isFalse);
      expect(payload.containsKey('paidAmount'), isFalse);
      expect(payload.containsKey('imagePaths'), isFalse);

      final localAfter = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM ${SyncFoundationTables.changes} WHERE origin='local'",
      ))
          .single['c'] as int;
      expect(localAfter, localBefore);
    } finally {
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });
}
