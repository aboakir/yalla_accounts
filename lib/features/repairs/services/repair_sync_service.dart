import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_contract_v3.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';

class RepairSyncService {
  RepairSyncService._();

  static Future<void> applyInbound(
    DatabaseExecutor executor,
    InboundSyncChange change,
  ) async {
    if (executor is! Transaction) {
      throw ArgumentError('Repair inbound sync requires a transaction.');
    }
    switch (change.entityType) {
      case 'repair':
        await _applyRepair(executor, change);
        return;
      case 'repair_line':
        await _applyLine(executor, change);
        return;
      case 'repair_workflow':
        await _applyWorkflow(executor, change);
        return;
      default:
        throw StateError('SYNC_REPAIR_UNSUPPORTED_ENTITY:${change.entityType}');
    }
  }

  static Future<Map<String, Object?>?> _identity(
    DatabaseExecutor db,
    String entityType,
    String entityUuid,
  ) async {
    final rows = await db.query(
      SyncFoundationTables.registry,
      where: 'entity_type=? AND entity_uuid=?',
      whereArgs: [entityType, entityUuid],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  static void _requireNextRevision(
    Map<String, Object?>? identity,
    int revision,
  ) {
    if (identity == null) {
      if (revision != 1) throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
      return;
    }
    final local = (identity['revision'] as num?)?.toInt() ?? -1;
    if (local + 1 != revision) {
      throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
    }
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool _restoreIntent(Map<String, Object?> payload) =>
      payload[SyncContractV3.tombstoneRestoreMarker] == true;
  static Future<int?> _customerIdForPartyUuid(
    DatabaseExecutor db,
    String? partyUuid,
  ) async {
    if (partyUuid == null) return null;
    final party = await _identity(db, 'party', partyUuid);
    if (party == null) throw StateError('SYNC_REPAIR_PARTY_MISSING');
    final partyId = party['local_id']!.toString();
    final roles = await db.query(
      'party_roles',
      columns: const ['legacy_id'],
      where: 'party_id=? AND role=?',
      whereArgs: [partyId, 'CUSTOMER'],
      limit: 1,
    );
    if (roles.isEmpty) throw StateError('SYNC_REPAIR_CUSTOMER_ROLE_MISSING');
    final raw = roles.single['legacy_id'];
    final id = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (id == null) throw StateError('SYNC_REPAIR_CUSTOMER_ID_INVALID');
    return id;
  }

  static Future<Map<String, Object?>> _vehicleForUuid(
    DatabaseExecutor db,
    String? vehicleUuid,
  ) async {
    if (vehicleUuid == null) throw StateError('SYNC_REPAIR_VEHICLE_MISSING');
    final identity = await _identity(db, 'vehicle', vehicleUuid);
    if (identity == null) throw StateError('SYNC_REPAIR_VEHICLE_MISSING');
    final localId = int.tryParse(identity['local_id']!.toString());
    if (localId == null) throw StateError('SYNC_REPAIR_VEHICLE_ID_INVALID');
    final rows = await db.query(
      'vehicles',
      where: 'id=?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('SYNC_REPAIR_VEHICLE_MISSING');
    return Map<String, Object?>.from(rows.single);
  }

  static Future<String> _repairIdForUuid(
    DatabaseExecutor db,
    String repairUuid,
  ) async {
    final identity = await _identity(db, 'repair', repairUuid);
    if (identity == null) throw StateError('SYNC_REPAIR_PARENT_MISSING');
    return identity['local_id']!.toString();
  }

  static Future<void> _applyRepair(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'repair', change.entityUuid);
    _requireNextRevision(identity, change.revision);
    final localId = identity?['local_id']?.toString() ?? change.entityUuid;
    if (change.operation == 'DELETE') {
      if (identity == null) throw StateError('SYNC_REPAIR_DELETE_MISSING');
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'repair',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn.update(
            'repairs',
            {
              'is_active': 0,
              'isArchived': 1,
              'updated_at': change.occurredAt.toUtc().toIso8601String(),
            },
            where: 'id=? AND COALESCE(is_active,1)=1',
            whereArgs: [localId],
          );
          if (changed != 1) throw StateError('SYNC_REPAIR_DELETE_MISSING');
        },
      );
      return;
    }

    final partyUuid = _text(payload['customer_party_uuid']);
    final vehicleUuid = _text(payload['vehicle_entity_uuid']);
    final clientId = await _customerIdForPartyUuid(txn, partyUuid);
    final vehicle = await _vehicleForUuid(txn, vehicleUuid);
    final now = change.occurredAt.toUtc().toIso8601String();
    final restore = _restoreIntent(payload);
    if (identity?['is_voided'] == 1 && !restore) {
      throw StateError('SYNC_REPAIR_RESTORE_REQUIRED');
    }
    if (identity?['is_voided'] != 1 && restore) {
      throw StateError('SYNC_REPAIR_RESTORE_WITHOUT_TOMBSTONE');
    }

    const allowed = <String>{
      'vehicleModel',
      'vehicleType',
      'vehicleNumber',
      'receivedDate',
      'beneficiaryType',
      'beneficiaryName',
      'insuranceStatus',
      'insurance_follow_up_status',
      'repairType',
      'vehicleStatus',
      'notes',
      'isArchived',
      'status',
      'quote_number',
      'quote_valid_until',
      'approved_at',
      'approved_by',
      'odometer',
      'fuel_level',
      'previous_damage',
      'intake_completed_at',
      'created_at',
      'updated_at',
    };
    final values = <String, Object?>{
      for (final entry in payload.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
      'client_id': clientId,
      'customer_party_uuid': partyUuid,
      'vehicle_entity_uuid': vehicleUuid,
      'is_active': 1,
      'updated_at': now,
    };
    values['vehicleNumber'] ??= vehicle['number'];
    values['vehicleType'] ??= vehicle['type'];
    values['vehicleModel'] ??= vehicle['model'];
    if (restore) values['isArchived'] = 0;

    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'repair',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows = await txn.query(
          'repairs',
          where: 'id=?',
          whereArgs: [localId],
          limit: 1,
        );
        if (rows.isEmpty) {
          values['created_at'] ??= now;
          await txn.insert(
              'repairs',
              {
                'id': localId,
                ...values,
              },
              conflictAlgorithm: ConflictAlgorithm.abort);
        } else {
          await txn.update(
            'repairs',
            values,
            where: 'id=?',
            whereArgs: [localId],
          );
        }
      },
    );
    await _ensureRevisionApplied(
      txn,
      'repair',
      change.entityUuid,
      change.revision,
      now,
    );
  }

  static Future<void> _applyLine(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final parentUuid = _text(payload['repair_entity_uuid']);
    if (parentUuid == null) throw StateError('SYNC_REPAIR_PARENT_UUID_MISSING');
    final repairId = await _repairIdForUuid(txn, parentUuid);
    final identity = await _identity(txn, 'repair_line', change.entityUuid);
    _requireNextRevision(identity, change.revision);
    final localId = identity?['local_id']?.toString() ?? change.entityUuid;
    final restore = _restoreIntent(payload);
    if (change.operation != 'DELETE') {
      if (identity?['is_voided'] == 1 && !restore) {
        throw StateError('SYNC_REPAIR_LINE_RESTORE_REQUIRED');
      }
      if (identity?['is_voided'] != 1 && restore) {
        throw StateError('SYNC_REPAIR_LINE_RESTORE_WITHOUT_TOMBSTONE');
      }
    }

    if (change.operation == 'DELETE') {
      if (identity == null) throw StateError('SYNC_REPAIR_LINE_DELETE_MISSING');
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'repair_line',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn.delete(
            'repair_lines',
            where: 'id=?',
            whereArgs: [localId],
          );
          if (changed != 1) throw StateError('SYNC_REPAIR_LINE_DELETE_MISSING');
        },
      );
      return;
    }

    final lineType = _text(payload['line_type']);
    final name = _text(payload['name']);
    final qty = (payload['qty'] as num?)?.toDouble() ??
        double.tryParse('${payload['qty']}');
    final price = (payload['price'] as num?)?.toDouble() ??
        double.tryParse('${payload['price']}');
    if (!{'work', 'part'}.contains(lineType) ||
        name == null ||
        qty == null ||
        qty <= 0 ||
        price == null ||
        price < 0) {
      throw const FormatException('Repair line payload is invalid.');
    }
    final total = double.parse((qty * price).toStringAsFixed(2));
    final now = change.occurredAt.toUtc().toIso8601String();
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'repair_line',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final values = <String, Object?>{
          'repair_id': repairId,
          'line_type': lineType,
          'name': name,
          'qty': qty,
          'price': price,
          'total': total,
          'notes': _text(payload['notes']),
          'created_at': _text(payload['created_at']) ?? now,
        };
        final rows = await txn.query(
          'repair_lines',
          where: 'id=?',
          whereArgs: [localId],
          limit: 1,
        );
        if (rows.isEmpty) {
          await txn.insert(
              'repair_lines',
              {
                'id': localId,
                ...values,
              },
              conflictAlgorithm: ConflictAlgorithm.abort);
        } else {
          await txn.update(
            'repair_lines',
            values,
            where: 'id=?',
            whereArgs: [localId],
          );
        }
      },
    );
  }

  static Future<void> _applyWorkflow(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final parentUuid = _text(payload['repair_entity_uuid']);
    if (parentUuid == null) throw StateError('SYNC_REPAIR_PARENT_UUID_MISSING');
    final repairId = await _repairIdForUuid(txn, parentUuid);
    final identity = await _identity(txn, 'repair_workflow', change.entityUuid);
    _requireNextRevision(identity, change.revision);
    if (identity != null && identity['local_id']?.toString() != repairId) {
      throw StateError('SYNC_REPAIR_WORKFLOW_PARENT_CONFLICT');
    }
    final existingAtParent = await txn.query(
      SyncFoundationTables.registry,
      columns: const ['entity_uuid'],
      where: 'entity_type=? AND local_id=?',
      whereArgs: ['repair_workflow', repairId],
      limit: 1,
    );
    if (identity == null &&
        existingAtParent.isNotEmpty &&
        existingAtParent.single['entity_uuid'] != change.entityUuid) {
      throw StateError('SYNC_REPAIR_WORKFLOW_IDENTITY_CONFLICT');
    }
    final restore = _restoreIntent(payload);
    if (change.operation != 'DELETE') {
      if (identity?['is_voided'] == 1 && !restore) {
        throw StateError('SYNC_REPAIR_WORKFLOW_RESTORE_REQUIRED');
      }
      if (identity?['is_voided'] != 1 && restore) {
        throw StateError('SYNC_REPAIR_WORKFLOW_RESTORE_WITHOUT_TOMBSTONE');
      }
    }

    if (change.operation == 'DELETE') {
      if (identity == null) {
        throw StateError('SYNC_REPAIR_WORKFLOW_DELETE_MISSING');
      }
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'repair_workflow',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn.delete(
            'repair_workflow',
            where: 'repair_id=?',
            whereArgs: [repairId],
          );
          if (changed != 1) {
            throw StateError('SYNC_REPAIR_WORKFLOW_DELETE_MISSING');
          }
        },
      );
      return;
    }

    final columns = (await txn.rawQuery(
      'PRAGMA table_info(repair_workflow)',
    ))
        .map((row) => row['name']!.toString())
        .toSet();
    final values = <String, Object?>{
      for (final entry in payload.entries)
        if (columns.contains(entry.key) &&
            entry.key != 'repair_id' &&
            entry.key != 'responsible_employee_id' &&
            entry.key != SyncContractV3.tombstoneRestoreMarker)
          entry.key: entry.value,
      'repair_id': repairId,
    };
    values.putIfAbsent('stage', () => 'DRAFT');
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'repair_workflow',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows = await txn.query(
          'repair_workflow',
          where: 'repair_id=?',
          whereArgs: [repairId],
          limit: 1,
        );
        if (rows.isEmpty) {
          await txn.insert(
            'repair_workflow',
            values,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          final update = Map<String, Object?>.from(values)..remove('repair_id');
          await txn.update(
            'repair_workflow',
            update,
            where: 'repair_id=?',
            whereArgs: [repairId],
          );
        }
      },
    );
  }

  static Future<void> _ensureRevisionApplied(
    DatabaseExecutor db,
    String entityType,
    String entityUuid,
    int revision,
    String updatedAt,
  ) async {
    final identity = await _identity(db, entityType, entityUuid);
    if (identity == null) throw StateError('SYNC_REMOTE_IDENTITY_MISSING');
    final current = (identity['revision'] as num?)?.toInt() ?? -1;
    if (current == revision) return;
    if (current + 1 != revision) {
      throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
    }
    await db.update(
      SyncFoundationTables.registry,
      {'revision': revision, 'updated_at': updatedAt},
      where: 'entity_type=? AND entity_uuid=? AND revision=?',
      whereArgs: [entityType, entityUuid, current],
    );
  }
}
