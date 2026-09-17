import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/tables/inventory_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_contract_v3.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';

class InventorySyncService {
  InventorySyncService._();

  static Future<void> applyInbound(
    DatabaseExecutor executor,
    InboundSyncChange change,
  ) async {
    if (executor is! Transaction) {
      throw ArgumentError('Inventory inbound sync requires a transaction.');
    }
    switch (change.entityType) {
      case 'inventory_item':
        await _applyItem(executor, change);
        return;
      case 'inventory_warehouse':
        await _applyWarehouse(executor, change);
        return;
      case 'inventory_movement':
        await _applyMovement(executor, change);
        return;
      case 'inventory_item_alternative':
        await _applyAlternative(executor, change);
        return;
      case 'inventory_item_compatibility':
        await _applyCompatibility(executor, change);
        return;
      default:
        throw StateError(
          'SYNC_INVENTORY_UNSUPPORTED_ENTITY:${change.entityType}',
        );
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
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double _number(Object? value, String code) {
    final result = value is num ? value.toDouble() : double.tryParse('$value');
    if (result == null || !result.isFinite) throw StateError(code);
    return result;
  }

  static bool _restore(Map<String, Object?> payload) =>
      payload[SyncContractV3.tombstoneRestoreMarker] == true;

  static Future<int> _localIdForUuid(
    DatabaseExecutor db,
    String entityType,
    String entityUuid,
  ) async {
    final identity = await _identity(db, entityType, entityUuid);
    if (identity == null || identity['is_voided'] == 1) {
      throw StateError('SYNC_INVENTORY_PARENT_MISSING');
    }
    final id = int.tryParse(identity['local_id']?.toString() ?? '');
    if (id == null || id <= 0) {
      throw StateError('SYNC_INVENTORY_PARENT_INVALID');
    }
    return id;
  }

  static Future<void> _applyItem(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'inventory_item', change.entityUuid);
    _requireNextRevision(identity, change.revision);
    final restore = _restore(payload);

    if (change.operation == 'DELETE') {
      if (identity == null) {
        throw StateError('SYNC_INVENTORY_ITEM_DELETE_MISSING');
      }
      final localId = int.parse(identity['local_id']!.toString());
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'inventory_item',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn.update(
            InventoryTables.items,
            {
              'is_active': 0,
              'updated_at': change.occurredAt.toUtc().toIso8601String(),
            },
            where: 'id=? AND is_active=1',
            whereArgs: [localId],
          );
          if (changed != 1) {
            throw StateError('SYNC_INVENTORY_ITEM_DELETE_MISSING');
          }
        },
      );
      return;
    }
    if (identity?['is_voided'] == 1 && !restore) {
      throw StateError('SYNC_INVENTORY_ITEM_RESTORE_REQUIRED');
    }
    if (identity?['is_voided'] != 1 && restore) {
      throw StateError('SYNC_INVENTORY_ITEM_RESTORE_WITHOUT_TOMBSTONE');
    }
    final name = _text(payload['name']);
    if (name == null) throw StateError('SYNC_INVENTORY_ITEM_INVALID');
    final itemKind = _text(payload['item_kind']) ?? 'PART';
    if (!const {'PART', 'RAW_MATERIAL', 'TOOL', 'OTHER'}.contains(itemKind)) {
      throw StateError('SYNC_INVENTORY_ITEM_INVALID');
    }
    final now = change.occurredAt.toUtc().toIso8601String();
    final values = <String, Object?>{
      'name': name,
      'sku': _text(payload['sku']),
      'oem_number': _text(payload['oem_number']),
      'barcode': _text(payload['barcode']),
      'item_kind': itemKind,
      'unit': _text(payload['unit']) ?? 'pcs',
      'category': _text(payload['category']),
      'origin_country': _text(payload['origin_country']),
      'supplier_name': _text(payload['supplier_name']),
      'default_purchase_price': payload['default_purchase_price'],
      'default_selling_price': payload['default_selling_price'],
      'description': _text(payload['description']),
      'is_active': 1,
      'updated_at': now,
    };
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'inventory_item',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        if (identity == null) {
          await txn.insert(InventoryTables.items, {
            ...values,
            'created_at': _text(payload['created_at']) ?? now,
          });
        } else {
          await txn.update(
            InventoryTables.items,
            values,
            where: 'id=?',
            whereArgs: [int.parse(identity['local_id']!.toString())],
          );
        }
      },
    );
  }

  static Future<void> _applyWarehouse(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(
      txn,
      'inventory_warehouse',
      change.entityUuid,
    );
    _requireNextRevision(identity, change.revision);
    final restore = _restore(payload);
    if (change.operation == 'DELETE') {
      if (identity == null) {
        throw StateError('SYNC_INVENTORY_WAREHOUSE_DELETE_MISSING');
      }
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'inventory_warehouse',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn.update(
            InventoryTables.warehouses,
            {
              'is_active': 0,
              'updated_at': change.occurredAt.toUtc().toIso8601String(),
            },
            where: 'id=? AND is_active=1',
            whereArgs: [int.parse(identity['local_id']!.toString())],
          );
          if (changed != 1) {
            throw StateError('SYNC_INVENTORY_WAREHOUSE_DELETE_MISSING');
          }
        },
      );
      return;
    }
    if (identity?['is_voided'] == 1 && !restore) {
      throw StateError('SYNC_INVENTORY_WAREHOUSE_RESTORE_REQUIRED');
    }
    if (identity?['is_voided'] != 1 && restore) {
      throw StateError('SYNC_INVENTORY_WAREHOUSE_RESTORE_WITHOUT_TOMBSTONE');
    }
    final code = _text(payload['code'])?.toUpperCase();
    final name = _text(payload['name']);
    if (code == null || name == null) {
      throw StateError('SYNC_INVENTORY_WAREHOUSE_INVALID');
    }
    final now = change.occurredAt.toUtc().toIso8601String();
    final values = <String, Object?>{
      'code': code,
      'name': name,
      'branch_code': _text(payload['branch_code']),
      'location': _text(payload['location']),
      'is_active': 1,
      'updated_at': now,
    };
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'inventory_warehouse',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        if (identity == null) {
          await txn.insert(InventoryTables.warehouses, {
            ...values,
            'created_at': _text(payload['created_at']) ?? now,
          });
        } else {
          await txn.update(
            InventoryTables.warehouses,
            values,
            where: 'id=?',
            whereArgs: [int.parse(identity['local_id']!.toString())],
          );
        }
      },
    );
  }

  static Future<void> _applyMovement(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    if (change.operation == 'DELETE' || _restore(payload)) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_APPEND_ONLY');
    }
    final identity = await _identity(
      txn,
      'inventory_movement',
      change.entityUuid,
    );
    if (identity != null || change.revision != 1) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_APPEND_ONLY');
    }
    final itemUuid = _text(payload['item_entity_uuid']);
    final warehouseUuid = _text(payload['warehouse_entity_uuid']);
    if (itemUuid == null || warehouseUuid == null) {
      throw StateError('SYNC_INVENTORY_PARENT_UUID_MISSING');
    }
    final itemId = await _localIdForUuid(txn, 'inventory_item', itemUuid);
    final warehouseId = await _localIdForUuid(
      txn,
      'inventory_warehouse',
      warehouseUuid,
    );
    final type = _text(payload['movement_type']);
    if (type == null || !InventoryTables.movementTypes.contains(type)) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_INVALID');
    }
    final onHandDelta = _number(
      payload['on_hand_delta'],
      'SYNC_INVENTORY_MOVEMENT_INVALID',
    );
    final reservedDelta = _number(
      payload['reserved_delta'] ?? 0,
      'SYNC_INVENTORY_MOVEMENT_INVALID',
    );
    _validateMovement(type, onHandDelta, reservedDelta);
    final occurredAt = _text(payload['occurred_at']);
    if (occurredAt == null || DateTime.tryParse(occurredAt) == null) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_INVALID');
    }
    final now = change.occurredAt.toUtc().toIso8601String();
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'inventory_movement',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        await txn.insert(InventoryTables.movements, {
          'item_id': itemId,
          'item_entity_uuid': itemUuid,
          'warehouse_id': warehouseId,
          'warehouse_entity_uuid': warehouseUuid,
          'movement_type': type,
          'on_hand_delta': onHandDelta,
          'reserved_delta': reservedDelta,
          'unit_cost': payload['unit_cost'],
          'landed_cost': payload['landed_cost'],
          'currency_code': _text(payload['currency_code']),
          'source_entity_type': _text(payload['source_entity_type']),
          'source_entity_uuid': _text(payload['source_entity_uuid']),
          'source_reference': _text(payload['source_reference']),
          'related_movement_uuid': _text(payload['related_movement_uuid']),
          'occurred_at': occurredAt,
          'note': _text(payload['note']),
          'created_at': _text(payload['created_at']) ?? now,
        });
      },
    );
  }

  static Future<void> _applyAlternative(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(
      txn,
      'inventory_item_alternative',
      change.entityUuid,
    );
    _requireNextRevision(identity, change.revision);
    if (change.operation == 'DELETE') {
      if (identity == null) {
        throw StateError('SYNC_INVENTORY_ALTERNATIVE_DELETE_MISSING');
      }
      await _setProjectionActive(
        txn,
        change,
        identity,
        InventoryTables.alternatives,
        false,
      );
      return;
    }
    final restore = _restore(payload);
    if (identity?['is_voided'] == 1 && !restore) {
      throw StateError('SYNC_INVENTORY_ALTERNATIVE_RESTORE_REQUIRED');
    }
    if (identity?['is_voided'] != 1 && restore) {
      throw StateError('SYNC_INVENTORY_ALTERNATIVE_RESTORE_WITHOUT_TOMBSTONE');
    }
    final itemUuid = _text(payload['item_entity_uuid']);
    final altUuid = _text(payload['alternative_item_entity_uuid']);
    if (itemUuid == null || altUuid == null || itemUuid == altUuid) {
      throw StateError('SYNC_INVENTORY_ALTERNATIVE_INVALID');
    }
    final itemId = await _localIdForUuid(txn, 'inventory_item', itemUuid);
    final altId = await _localIdForUuid(txn, 'inventory_item', altUuid);
    final now = change.occurredAt.toUtc().toIso8601String();
    final values = {
      'item_id': itemId,
      'item_entity_uuid': itemUuid,
      'alternative_item_id': altId,
      'alternative_item_entity_uuid': altUuid,
      'note': _text(payload['note']),
      'is_active': 1,
      'updated_at': now,
    };
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: change.entityType,
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        if (identity == null) {
          await txn.insert(InventoryTables.alternatives, {
            ...values,
            'created_at': _text(payload['created_at']) ?? now,
          });
        } else {
          await txn.update(
            InventoryTables.alternatives,
            values,
            where: 'id=?',
            whereArgs: [int.parse(identity['local_id']!.toString())],
          );
        }
      },
    );
  }

  static Future<void> _applyCompatibility(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(
      txn,
      'inventory_item_compatibility',
      change.entityUuid,
    );
    _requireNextRevision(identity, change.revision);
    if (change.operation == 'DELETE') {
      if (identity == null) {
        throw StateError('SYNC_INVENTORY_COMPATIBILITY_DELETE_MISSING');
      }
      await _setProjectionActive(
        txn,
        change,
        identity,
        InventoryTables.compatibility,
        false,
      );
      return;
    }
    final restore = _restore(payload);
    if (identity?['is_voided'] == 1 && !restore) {
      throw StateError('SYNC_INVENTORY_COMPATIBILITY_RESTORE_REQUIRED');
    }
    if (identity?['is_voided'] != 1 && restore) {
      throw StateError(
        'SYNC_INVENTORY_COMPATIBILITY_RESTORE_WITHOUT_TOMBSTONE',
      );
    }
    final itemUuid = _text(payload['item_entity_uuid']);
    if (itemUuid == null) {
      throw StateError('SYNC_INVENTORY_COMPATIBILITY_INVALID');
    }
    final itemId = await _localIdForUuid(txn, 'inventory_item', itemUuid);
    final yearFrom = payload['year_from'] == null
        ? null
        : (payload['year_from'] as num?)?.toInt();
    final yearTo = payload['year_to'] == null
        ? null
        : (payload['year_to'] as num?)?.toInt();
    if (yearFrom != null && yearTo != null && yearFrom > yearTo) {
      throw StateError('SYNC_INVENTORY_COMPATIBILITY_INVALID');
    }
    final now = change.occurredAt.toUtc().toIso8601String();
    final values = <String, Object?>{
      'item_id': itemId,
      'item_entity_uuid': itemUuid,
      'make': _text(payload['make']),
      'model': _text(payload['model']),
      'year_from': yearFrom,
      'year_to': yearTo,
      'engine': _text(payload['engine']),
      'body': _text(payload['body']),
      'note': _text(payload['note']),
      'is_active': 1,
      'updated_at': now,
    };
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: change.entityType,
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        if (identity == null) {
          await txn.insert(InventoryTables.compatibility, {
            ...values,
            'created_at': _text(payload['created_at']) ?? now,
          });
        } else {
          await txn.update(
            InventoryTables.compatibility,
            values,
            where: 'id=?',
            whereArgs: [int.parse(identity['local_id']!.toString())],
          );
        }
      },
    );
  }

  static Future<void> _setProjectionActive(
    Transaction txn,
    InboundSyncChange change,
    Map<String, Object?> identity,
    String table,
    bool active,
  ) async {
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: change.entityType,
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final changed = await txn.update(
          table,
          {
            'is_active': active ? 1 : 0,
            'updated_at': change.occurredAt.toUtc().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [int.parse(identity['local_id']!.toString())],
        );
        if (changed != 1) {
          throw StateError('SYNC_INVENTORY_PROJECTION_MISSING');
        }
      },
    );
  }

  static void _validateMovement(String type, double onHand, double reserved) {
    if (onHand == 0 && reserved == 0) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_INVALID');
    }
    const inbound = {
      'OPENING_BALANCE',
      'PURCHASE_RECEIPT',
      'RETURN_IN',
      'DISMANTLED_ALLOCATION',
      'TRANSFER_IN',
      'WARRANTY_IN',
    };
    const outbound = {'SALE', 'RETURN_OUT', 'TRANSFER_OUT', 'WARRANTY_OUT'};
    if (inbound.contains(type) && !(onHand > 0 && reserved == 0)) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_INVALID');
    }
    if (outbound.contains(type) && !(onHand < 0 && reserved == 0)) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_INVALID');
    }
    if (type == 'RESERVATION' && !(onHand == 0 && reserved > 0)) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_INVALID');
    }
    if (type == 'RELEASE' && !(onHand == 0 && reserved < 0)) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_INVALID');
    }
    if (type == 'ADJUSTMENT' && reserved != 0) {
      throw StateError('SYNC_INVENTORY_MOVEMENT_INVALID');
    }
  }
}
