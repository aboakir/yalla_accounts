import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';

class RepairSyncReferences {
  const RepairSyncReferences({
    required this.customerPartyUuid,
    required this.vehicleEntityUuid,
  });

  final String? customerPartyUuid;
  final String? vehicleEntityUuid;
}

class RepairSyncReferenceService {
  RepairSyncReferenceService._();

  static Future<RepairSyncReferences> resolve(
    DatabaseExecutor db, {
    required int? clientId,
    required int? vehicleId,
  }) async {
    if (!await SyncFoundationTables.isInstalled(db)) {
      return const RepairSyncReferences(
        customerPartyUuid: null,
        vehicleEntityUuid: null,
      );
    }
    String? partyUuid;
    if (clientId != null) {
      final partyId = await PartyTables.resolvePartyId(
        db,
        role: 'CUSTOMER',
        legacyId: clientId,
      );
      if (partyId != null) {
        final rows = await db.query(
          SyncFoundationTables.registry,
          columns: const ['entity_uuid'],
          where: 'entity_type=? AND local_id=?',
          whereArgs: ['party', partyId],
          limit: 1,
        );
        partyUuid = rows.isEmpty
            ? null
            : rows.single['entity_uuid']?.toString();
      }
    }

    String? vehicleUuid;
    if (vehicleId != null) {
      final rows = await db.query(
        SyncFoundationTables.registry,
        columns: const ['entity_uuid'],
        where: 'entity_type=? AND local_id=?',
        whereArgs: ['vehicle', vehicleId.toString()],
        limit: 1,
      );
      vehicleUuid = rows.isEmpty
          ? null
          : rows.single['entity_uuid']?.toString();
    }
    return RepairSyncReferences(
      customerPartyUuid: partyUuid,
      vehicleEntityUuid: vehicleUuid,
    );
  }

  static Future<int?> findVehicleId(
    DatabaseExecutor db, {
    required String number,
    int? clientId,
  }) async {
    final normalized = VehicleTables.normalizeNumber(number);
    if (normalized.isEmpty) return null;
    final rows = await db.query(
      VehicleTables.tableName,
      columns: const ['id'],
      where: clientId == null
          ? 'normalized_number=?'
          : 'normalized_number=? AND client_id=?',
      whereArgs: clientId == null ? [normalized] : [normalized, clientId],
      limit: 2,
    );
    if (rows.length != 1) return null;
    final raw = rows.single['id'];
    return raw is num ? raw.toInt() : int.tryParse('$raw');
  }
}
