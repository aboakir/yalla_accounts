import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

import '../models/vehicle.dart';

class DuplicateVehicleException implements Exception {
  const DuplicateVehicleException(this.number);

  final String number;

  @override
  String toString() => 'المركبة ذات الرقم $number موجودة مسبقًا';
}

class VehicleService {
  VehicleService._();

  static Future<List<Vehicle>> getAllVehicles({String? query}) async {
    final db = await DBService.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.name AS client_name
      FROM vehicles v
      LEFT JOIN clients c ON c.id = v.client_id
      WHERE COALESCE(v.is_active,1)=1
      ORDER BY LOWER(v.type) ASC, v.number ASC
    ''');

    final vehicles = <Vehicle>[];
    for (final row in rows) {
      final base = Vehicle.fromMap(row);
      final history = await getHistoryByNumber(
        base.number,
        database: db,
      );
      String? profileImagePath;
      for (final repair in history) {
        final canonicalThumbnail = repair.thumbnailPath?.trim();
        final candidates = <String?>[
          canonicalThumbnail,
          ...repair.imagePaths,
        ];
        for (final raw in candidates) {
          final candidate = raw?.trim();
          if (candidate == null || candidate.isEmpty) continue;
          final resolved =
              await YallaStorageService.resolveExistingPath(candidate);
          if (resolved != null) {
            profileImagePath = candidate;
            break;
          }
        }
        if (profileImagePath != null) break;
      }

      vehicles.add(
        base.copyWith(
          repairCount: history.length,
          lastReceivedDate: history.isEmpty ? null : history.first.receivedDate,
          profileImagePath: profileImagePath,
        ),
      );
    }

    return vehicles
        .where((vehicle) => matchesQuery(vehicle, query ?? ''))
        .toList(growable: false);
  }

  static bool matchesQuery(Vehicle vehicle, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final plate = VehicleTables.normalizeNumber(q);
    return (plate.isNotEmpty &&
            VehicleTables.normalizeNumber(vehicle.number).contains(plate)) ||
        vehicle.type.toLowerCase().contains(q) ||
        vehicle.model.toLowerCase().contains(q) ||
        vehicle.clientName.toLowerCase().contains(q);
  }

  static Future<String?> _ownerPartyUuidForClient(
    DatabaseExecutor db,
    int? clientId,
  ) async {
    if (clientId == null || !await SyncFoundationTables.isInstalled(db)) {
      return null;
    }
    final partyId = await PartyTables.resolvePartyId(
      db,
      role: 'CUSTOMER',
      legacyId: clientId,
    );
    if (partyId == null) return null;
    final rows = await db.query(
      SyncFoundationTables.registry,
      columns: const ['entity_uuid'],
      where: 'entity_type=? AND local_id=?',
      whereArgs: ['party', partyId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['entity_uuid']?.toString();
  }

  static Future<List<Vehicle>> getByClientId(int clientId) async {
    final all = await getAllVehicles();
    return all
        .where((vehicle) => vehicle.clientId == clientId)
        .toList(growable: false);
  }

  static Future<int?> findDuplicateIdOn(
    DatabaseExecutor db,
    String number, {
    int? excludeId,
  }) async {
    final normalized = VehicleTables.normalizeNumber(number);
    if (normalized.isEmpty) return null;

    var where = 'normalized_number = ?';
    final args = <Object?>[normalized];

    if (excludeId != null) {
      where += ' AND id <> ?';
      args.add(excludeId);
    }

    final rows = await db.query(
      VehicleTables.tableName,
      columns: const ['id'],
      where: where,
      whereArgs: args,
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final value = rows.first['id'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static Future<int> insertVehicle(Vehicle vehicle) async {
    final id = await DBService.inTx<int>((txn) async {
      final duplicate = await findDuplicateIdOn(txn, vehicle.number);
      if (duplicate != null) {
        throw DuplicateVehicleException(vehicle.number);
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final ownerPartyUuid =
          await _ownerPartyUuidForClient(txn, vehicle.clientId);
      final id = await txn.insert(
        VehicleTables.tableName,
        {
          'normalized_number': VehicleTables.normalizeNumber(vehicle.number),
          'number': vehicle.number.trim(),
          'type': vehicle.type.trim(),
          'model': vehicle.model.trim(),
          'client_id': vehicle.clientId,
          'owner_party_uuid': ownerPartyUuid,
          'is_active': 1,
          'notes': vehicle.notes.trim(),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      if (!await SyncFoundationTables.isInstalled(txn)) {
        await OfflineOutboxService.enqueue(
          txn,
          channel: OfflineOutboxService.channelSync,
          operation: 'UPSERT',
          entityType: 'vehicle',
          entityId: id.toString(),
          idempotencyKey: 'vehicle:$id:create',
          payload: {
            'schema': 1,
            'entity_type': 'vehicle',
            'entity_id': id,
            'number': vehicle.number.trim(),
            'type': vehicle.type.trim(),
            'model': vehicle.model.trim(),
            'client_id': vehicle.clientId,
          },
        );
      }

      return id;
    });

    return id;
  }

  static Future<int> updateVehicle(Vehicle vehicle) async {
    final id = vehicle.id;
    if (id == null) {
      throw StateError('لا يمكن تعديل مركبة بدون رقم داخلي');
    }

    return DBService.inTx<int>((txn) async {
      final duplicate = await findDuplicateIdOn(
        txn,
        vehicle.number,
        excludeId: id,
      );
      if (duplicate != null) {
        throw DuplicateVehicleException(vehicle.number);
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final ownerPartyUuid =
          await _ownerPartyUuidForClient(txn, vehicle.clientId);
      final changed = await txn.update(
        VehicleTables.tableName,
        {
          'normalized_number': VehicleTables.normalizeNumber(vehicle.number),
          'number': vehicle.number.trim(),
          'type': vehicle.type.trim(),
          'model': vehicle.model.trim(),
          'client_id': vehicle.clientId,
          'owner_party_uuid': ownerPartyUuid,
          'notes': vehicle.notes.trim(),
          'updated_at': now,
        },
        where: 'id = ? AND COALESCE(is_active,1)=1',
        whereArgs: [id],
      );

      if (changed > 0 && !await SyncFoundationTables.isInstalled(txn)) {
        await OfflineOutboxService.enqueue(
          txn,
          channel: OfflineOutboxService.channelSync,
          operation: 'UPSERT',
          entityType: 'vehicle',
          entityId: id.toString(),
          idempotencyKey: 'vehicle:$id:update:$now',
          payload: {
            'schema': 1,
            'entity_type': 'vehicle',
            'entity_id': id,
            'number': vehicle.number.trim(),
            'type': vehicle.type.trim(),
            'model': vehicle.model.trim(),
            'client_id': vehicle.clientId,
          },
        );
      }

      return changed;
    });
  }

  static Future<int> upsertFromRepairOn(
    DatabaseExecutor db, {
    required String number,
    required String type,
    required String model,
    required int? clientId,
  }) async {
    final normalized = VehicleTables.normalizeNumber(number);
    if (normalized.isEmpty) {
      throw StateError('رقم المركبة مطلوب');
    }

    final ownerPartyUuid = await _ownerPartyUuidForClient(db, clientId);
    final existing = await db.query(
      VehicleTables.tableName,
      columns: const ['id', 'is_active', 'client_id'],
      where: 'normalized_number = ?',
      whereArgs: [normalized],
      limit: 1,
    );

    final now = DateTime.now().toUtc().toIso8601String();

    if (existing.isNotEmpty) {
      if (existing.first['is_active'] == 0) {
        throw StateError('VEHICLE_TOMBSTONE_RESTORE_REQUIRED');
      }
      final rawClientId = existing.first['client_id'];
      final existingClientId = rawClientId is num
          ? rawClientId.toInt()
          : int.tryParse(rawClientId?.toString() ?? '');
      if (existingClientId != null &&
          clientId != null &&
          existingClientId != clientId) {
        throw StateError('VEHICLE_OWNER_CONFLICT');
      }
      final rawId = existing.first['id'];
      final id = rawId is int
          ? rawId
          : rawId is num
              ? rawId.toInt()
              : int.parse(rawId.toString());

      await db.update(
        VehicleTables.tableName,
        {
          'number': number.trim(),
          if (type.trim().isNotEmpty) 'type': type.trim(),
          if (model.trim().isNotEmpty) 'model': model.trim(),
          if (clientId != null) 'client_id': clientId,
          if (ownerPartyUuid != null) 'owner_party_uuid': ownerPartyUuid,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    final id = await db.insert(
      VehicleTables.tableName,
      {
        'normalized_number': normalized,
        'number': number.trim(),
        'type': type.trim(),
        'model': model.trim(),
        'client_id': clientId,
        'owner_party_uuid': ownerPartyUuid,
        'is_active': 1,
        'notes': '',
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    if (!await SyncFoundationTables.isInstalled(db)) {
      await OfflineOutboxService.enqueue(
        db,
        channel: OfflineOutboxService.channelSync,
        operation: 'UPSERT',
        entityType: 'vehicle',
        entityId: id.toString(),
        idempotencyKey: 'vehicle:$id:create',
        payload: {
          'schema': 1,
          'entity_type': 'vehicle',
          'entity_id': id,
          'number': number.trim(),
          'type': type.trim(),
          'model': model.trim(),
          'client_id': clientId,
        },
      );
    }

    return id;
  }

  static Future<int> deactivateVehicle(int id) async {
    return DBService.inTx<int>((txn) async {
      final rows = await txn.query(
        VehicleTables.tableName,
        columns: const ['number', 'is_active'],
        where: 'id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['is_active'] == 0) return 0;
      final now = DateTime.now().toUtc().toIso8601String();
      final changed = await txn.update(
        VehicleTables.tableName,
        {'is_active': 0, 'updated_at': now},
        where: 'id=? AND COALESCE(is_active,1)=1',
        whereArgs: [id],
      );
      if (changed > 0 && !await SyncFoundationTables.isInstalled(txn)) {
        await OfflineOutboxService.enqueue(
          txn,
          channel: OfflineOutboxService.channelSync,
          operation: 'DELETE',
          entityType: 'vehicle',
          entityId: id.toString(),
          idempotencyKey: 'vehicle:$id:delete:$now',
          payload: {'schema': 1, 'entity_type': 'vehicle', 'entity_id': id},
        );
      }
      return changed;
    });
  }

  static Future<int> restoreVehicle(Vehicle vehicle) async {
    final id = vehicle.id;
    if (id == null) throw StateError('لا يمكن استعادة مركبة بدون رقم داخلي');
    return DBService.inTx<int>((txn) async {
      final duplicate =
          await findDuplicateIdOn(txn, vehicle.number, excludeId: id);
      if (duplicate != null) throw DuplicateVehicleException(vehicle.number);
      final ownerPartyUuid =
          await _ownerPartyUuidForClient(txn, vehicle.clientId);
      final now = DateTime.now().toUtc().toIso8601String();
      final changed = await txn.update(
        VehicleTables.tableName,
        {
          'normalized_number': VehicleTables.normalizeNumber(vehicle.number),
          'number': vehicle.number.trim(),
          'type': vehicle.type.trim(),
          'model': vehicle.model.trim(),
          'client_id': vehicle.clientId,
          'owner_party_uuid': ownerPartyUuid,
          'notes': vehicle.notes.trim(),
          'is_active': 1,
          'updated_at': now,
        },
        where: 'id=? AND is_active=0',
        whereArgs: [id],
      );
      if (changed > 0 && !await SyncFoundationTables.isInstalled(txn)) {
        await OfflineOutboxService.enqueue(
          txn,
          channel: OfflineOutboxService.channelSync,
          operation: 'UPSERT',
          entityType: 'vehicle',
          entityId: id.toString(),
          idempotencyKey: 'vehicle:$id:restore:$now',
          payload: {'schema': 1, 'entity_type': 'vehicle', 'entity_id': id},
        );
      }
      return changed;
    });
  }

  static Future<List<Repair>> getHistory(int vehicleId) async {
    final db = await DBService.database;
    final rows = await db.query(
      VehicleTables.tableName,
      columns: const ['number'],
      where: 'id = ?',
      whereArgs: [vehicleId],
      limit: 1,
    );
    if (rows.isEmpty) return const [];

    return getHistoryByNumber(
      rows.first['number']?.toString() ?? '',
      database: db,
    );
  }

  static Future<List<Repair>> getHistoryByNumber(
    String number, {
    DatabaseExecutor? database,
  }) async {
    final db = database ?? await DBService.database;
    final normalized = VehicleTables.normalizeNumber(number);
    if (normalized.isEmpty) return const [];

    final rows = await db.query(
      'repairs',
      where: 'vehicleNumber IS NOT NULL AND TRIM(vehicleNumber) <> ?',
      whereArgs: const [''],
      orderBy: 'receivedDate DESC, created_at DESC',
    );

    final matches = rows.where((row) {
      return VehicleTables.normalizeNumber(
            row['vehicleNumber']?.toString() ?? '',
          ) ==
          normalized;
    });

    return matches.map(Repair.fromMap).toList(growable: false);
  }
}
