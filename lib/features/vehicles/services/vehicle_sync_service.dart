import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';

class VehicleSyncService {
  VehicleSyncService._();

  static Future<void> applyInbound(
    DatabaseExecutor executor,
    InboundSyncChange change,
  ) async {
    if (executor is! Transaction) {
      throw ArgumentError('Vehicle inbound sync requires a transaction.');
    }
    if (change.entityType != 'vehicle') {
      throw StateError('SYNC_VEHICLE_UNSUPPORTED_ENTITY:${change.entityType}');
    }

    final registry = await executor.query(
      SyncFoundationTables.registry,
      where: 'entity_type=? AND entity_uuid=?',
      whereArgs: ['vehicle', change.entityUuid],
      limit: 1,
    );
    final existingRegistry = registry.isEmpty ? null : registry.single;
    if (existingRegistry == null && change.revision != 1) {
      throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
    }
    if (existingRegistry != null) {
      final localRevision =
          (existingRegistry['revision'] as num?)?.toInt() ?? -1;
      if (localRevision + 1 != change.revision) {
        throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
      }
    }

    final localId = existingRegistry == null
        ? null
        : int.tryParse(existingRegistry['local_id']!.toString());
    if (existingRegistry != null && localId == null) {
      throw StateError('SYNC_VEHICLE_LOCAL_ID_INVALID');
    }

    if (change.operation == 'DELETE') {
      if (localId == null) throw StateError('SYNC_VEHICLE_DELETE_MISSING');
      await SyncFoundationService.withRemoteMutation(
        executor,
        entityType: 'vehicle',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await executor.update(
            VehicleTables.tableName,
            {
              'is_active': 0,
              'updated_at': change.occurredAt.toUtc().toIso8601String(),
            },
            where: 'id=? AND COALESCE(is_active,1)=1',
            whereArgs: [localId],
          );
          if (changed != 1) {
            throw StateError('SYNC_VEHICLE_DELETE_MISSING');
          }
        },
      );
      return;
    }

    final payload = Map<String, Object?>.from(change.payload);
    final number = (payload['number'] ?? '').toString().trim();
    if (number.isEmpty) {
      throw const FormatException('Vehicle number is required.');
    }
    final normalized = VehicleTables.normalizeNumber(number);
    if (normalized.isEmpty) {
      throw const FormatException('Vehicle normalized number is invalid.');
    }

    final duplicates = await executor.query(
      VehicleTables.tableName,
      columns: const ['id'],
      where: localId == null
          ? 'normalized_number=?'
          : 'normalized_number=? AND id<>?',
      whereArgs: localId == null ? [normalized] : [normalized, localId],
      limit: 1,
    );
    if (duplicates.isNotEmpty) {
      throw StateError('SYNC_VEHICLE_PLATE_CONFLICT');
    }

    final ownerPartyUuid = _text(payload['owner_party_uuid']);
    final clientId = await _resolveLocalCustomer(executor, ownerPartyUuid);
    final now = change.occurredAt.toUtc().toIso8601String();
    final values = <String, Object?>{
      'normalized_number': normalized,
      'number': number,
      'type': _text(payload['type']) ?? '',
      'model': _text(payload['model']) ?? '',
      'client_id': clientId,
      'owner_party_uuid': ownerPartyUuid,
      'notes': _text(payload['notes']) ?? '',
      'is_active': 1,
      'updated_at': now,
    };
    await SyncFoundationService.withRemoteMutation(
      executor,
      entityType: 'vehicle',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        if (localId == null) {
          await executor.insert(VehicleTables.tableName, {
            ...values,
            'created_at': _text(payload['created_at']) ?? now,
          });
        } else {
          final changed = await executor.update(
            VehicleTables.tableName,
            values,
            where: 'id=?',
            whereArgs: [localId],
          );
          if (changed != 1) {
            throw StateError('SYNC_VEHICLE_LOCAL_ROW_MISSING');
          }
        }
      },
    );
  }

  static Future<int?> _resolveLocalCustomer(
    DatabaseExecutor db,
    String? ownerPartyUuid,
  ) async {
    if (ownerPartyUuid == null) return null;
    final party = await db.query(
      SyncFoundationTables.registry,
      columns: const ['local_id'],
      where: 'entity_type=? AND entity_uuid=? AND is_voided=0',
      whereArgs: ['party', ownerPartyUuid],
      limit: 1,
    );
    if (party.isEmpty) {
      throw StateError('SYNC_VEHICLE_OWNER_PARTY_MISSING');
    }
    final partyId = party.single['local_id']!.toString();
    final role = await db.query(
      'party_roles',
      columns: const ['legacy_id'],
      where: 'party_id=? AND role=?',
      whereArgs: [partyId, 'CUSTOMER'],
      limit: 1,
    );
    if (role.isEmpty) {
      throw StateError('SYNC_VEHICLE_OWNER_CUSTOMER_ROLE_MISSING');
    }
    final legacyId = role.single['legacy_id']!.toString();
    final parsed = int.tryParse(legacyId);
    if (parsed == null) {
      throw StateError('SYNC_VEHICLE_OWNER_CUSTOMER_ID_INVALID');
    }
    return parsed;
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
