import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
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
      ORDER BY LOWER(v.type) ASC, v.number ASC
    ''');

    final vehicles = <Vehicle>[];
    for (final row in rows) {
      final base = Vehicle.fromMap(row);
      final history = await getHistoryByNumber(
        base.number,
        database: db,
      );
      vehicles.add(
        base.copyWith(
          repairCount: history.length,
          lastReceivedDate: history.isEmpty ? null : history.first.receivedDate,
        ),
      );
    }

    final q = query?.trim().toLowerCase() ?? '';
    if (q.isEmpty) return vehicles;

    return vehicles.where((vehicle) {
      return vehicle.number.toLowerCase().contains(q) ||
          vehicle.type.toLowerCase().contains(q) ||
          vehicle.model.toLowerCase().contains(q) ||
          vehicle.clientName.toLowerCase().contains(q);
    }).toList(growable: false);
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
      final id = await txn.insert(
        VehicleTables.tableName,
        {
          'normalized_number': VehicleTables.normalizeNumber(vehicle.number),
          'number': vehicle.number.trim(),
          'type': vehicle.type.trim(),
          'model': vehicle.model.trim(),
          'client_id': vehicle.clientId,
          'notes': vehicle.notes.trim(),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

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
      final changed = await txn.update(
        VehicleTables.tableName,
        {
          'normalized_number': VehicleTables.normalizeNumber(vehicle.number),
          'number': vehicle.number.trim(),
          'type': vehicle.type.trim(),
          'model': vehicle.model.trim(),
          'client_id': vehicle.clientId,
          'notes': vehicle.notes.trim(),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (changed > 0) {
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

    final existing = await db.query(
      VehicleTables.tableName,
      columns: const ['id'],
      where: 'normalized_number = ?',
      whereArgs: [normalized],
      limit: 1,
    );

    final now = DateTime.now().toUtc().toIso8601String();

    if (existing.isNotEmpty) {
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
        'notes': '',
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

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

    return id;
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
