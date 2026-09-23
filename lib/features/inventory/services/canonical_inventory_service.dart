import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/tables/inventory_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';

class InventoryStockBalance {
  const InventoryStockBalance({
    required this.onHand,
    required this.reserved,
    required this.available,
  });

  final double onHand;
  final double reserved;
  final double available;
}

class CanonicalInventoryService {
  CanonicalInventoryService._();

  static Future<Database> get _database async => DBService.database;

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static Future<int> createItem({
    required String name,
    String itemKind = 'PART',
    String unit = 'pcs',
    String? sku,
    String? oemNumber,
    String? barcode,
    String? category,
    String? originCountry,
    double? defaultPurchasePrice,
    double? defaultSellingPrice,
    String? description,
  }) async {
    final itemName = name.trim();
    if (itemName.isEmpty) throw ArgumentError.value(name, 'name');
    if (!const {'PART', 'RAW_MATERIAL', 'TOOL', 'OTHER'}.contains(itemKind)) {
      throw ArgumentError.value(itemKind, 'itemKind');
    }
    final db = await _database;
    return SyncFoundationService.transaction(db, (txn) async {
      final now = _now();
      return txn.insert(InventoryTables.items, {
        'name': itemName,
        'sku': _nullable(sku),
        'oem_number': _nullable(oemNumber),
        'barcode': _nullable(barcode),
        'item_kind': itemKind,
        'unit': unit.trim().isEmpty ? 'pcs' : unit.trim(),
        'category': _nullable(category),
        'origin_country': _nullable(originCountry),
        'default_purchase_price': defaultPurchasePrice,
        'default_selling_price': defaultSellingPrice,
        'description': _nullable(description),
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  static Future<int> createWarehouse({
    required String code,
    required String name,
    String? branchCode,
    String? location,
  }) async {
    final normalizedCode = code.trim().toUpperCase();
    final warehouseName = name.trim();
    if (normalizedCode.isEmpty || warehouseName.isEmpty) {
      throw ArgumentError('Warehouse code/name must not be blank.');
    }
    final db = await _database;
    return SyncFoundationService.transaction(db, (txn) async {
      final now = _now();
      return txn.insert(InventoryTables.warehouses, {
        'code': normalizedCode,
        'name': warehouseName,
        'branch_code': _nullable(branchCode),
        'location': _nullable(location),
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  static Future<int> addAlternative({
    required int itemId,
    required int alternativeItemId,
    String? note,
  }) async {
    if (itemId == alternativeItemId) {
      throw ArgumentError('An inventory item cannot be its own alternative.');
    }
    final db = await _database;
    return SyncFoundationService.transaction(db, (txn) async {
      final itemUuid = await _publishableUuid(
        txn,
        table: InventoryTables.items,
        entityType: 'inventory_item',
        localId: itemId,
      );
      final alternativeUuid = await _publishableUuid(
        txn,
        table: InventoryTables.items,
        entityType: 'inventory_item',
        localId: alternativeItemId,
      );
      final now = _now();
      return txn.insert(InventoryTables.alternatives, {
        'item_id': itemId,
        'item_entity_uuid': itemUuid,
        'alternative_item_id': alternativeItemId,
        'alternative_item_entity_uuid': alternativeUuid,
        'note': _nullable(note),
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  static Future<int> addCompatibility({
    required int itemId,
    String? make,
    String? model,
    int? yearFrom,
    int? yearTo,
    String? engine,
    String? body,
    String? note,
  }) async {
    if (yearFrom != null && yearTo != null && yearFrom > yearTo) {
      throw ArgumentError('yearFrom cannot be greater than yearTo.');
    }
    final db = await _database;
    return SyncFoundationService.transaction(db, (txn) async {
      final itemUuid = await _publishableUuid(
        txn,
        table: InventoryTables.items,
        entityType: 'inventory_item',
        localId: itemId,
      );
      final now = _now();
      return txn.insert(InventoryTables.compatibility, {
        'item_id': itemId,
        'item_entity_uuid': itemUuid,
        'make': _nullable(make),
        'model': _nullable(model),
        'year_from': yearFrom,
        'year_to': yearTo,
        'engine': _nullable(engine),
        'body': _nullable(body),
        'note': _nullable(note),
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  static Future<int> recordMovement({
    required int itemId,
    required int warehouseId,
    required String movementType,
    required double onHandDelta,
    double reservedDelta = 0,
    double? unitCost,
    double? landedCost,
    String? currencyCode,
    String? sourceEntityType,
    String? sourceEntityUuid,
    String? sourceReference,
    String? relatedMovementUuid,
    DateTime? occurredAt,
    String? note,
  }) async {
    if (movementType == 'OPENING_BALANCE') {
      throw ArgumentError(
        'Opening balances are reserved for migration/import.',
      );
    }
    _validateMovement(
      movementType,
      onHandDelta: onHandDelta,
      reservedDelta: reservedDelta,
    );
    final db = await _database;
    return SyncFoundationService.transaction(db, (txn) async {
      return _recordMovementInTransaction(
        txn,
        itemId: itemId,
        warehouseId: warehouseId,
        movementType: movementType,
        onHandDelta: onHandDelta,
        reservedDelta: reservedDelta,
        unitCost: unitCost,
        landedCost: landedCost,
        currencyCode: currencyCode,
        sourceEntityType: sourceEntityType,
        sourceEntityUuid: sourceEntityUuid,
        sourceReference: sourceReference,
        relatedMovementUuid: relatedMovementUuid,
        occurredAt: occurredAt,
        note: note,
      );
    });
  }

  static Future<int> recordMovementOn(
    Transaction txn, {
    required int itemId,
    required int warehouseId,
    required String movementType,
    required double onHandDelta,
    double reservedDelta = 0,
    double? unitCost,
    double? landedCost,
    String? currencyCode,
    String? sourceEntityType,
    String? sourceEntityUuid,
    String? sourceReference,
    String? relatedMovementUuid,
    DateTime? occurredAt,
    String? note,
    bool skipAvailabilityCheck = false,
  }) {
    return _recordMovementInTransaction(
      txn,
      itemId: itemId,
      warehouseId: warehouseId,
      movementType: movementType,
      onHandDelta: onHandDelta,
      reservedDelta: reservedDelta,
      unitCost: unitCost,
      landedCost: landedCost,
      currencyCode: currencyCode,
      sourceEntityType: sourceEntityType,
      sourceEntityUuid: sourceEntityUuid,
      sourceReference: sourceReference,
      relatedMovementUuid: relatedMovementUuid,
      occurredAt: occurredAt,
      note: note,
      skipAvailabilityCheck: skipAvailabilityCheck,
    );
  }

  static Future<List<int>> transfer({
    required int itemId,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double quantity,
    DateTime? occurredAt,
    String? note,
  }) async {
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('Transfer warehouses must be different.');
    }
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity');
    }
    final db = await _database;
    return SyncFoundationService.transaction(db, (txn) async {
      await _assertAvailable(txn, itemId, fromWarehouseId, quantity);
      final transferCost = await _weightedAverageUnitCost(
        txn,
        itemId: itemId,
        warehouseId: fromWarehouseId,
      );
      final outId = await _recordMovementInTransaction(
        txn,
        itemId: itemId,
        warehouseId: fromWarehouseId,
        movementType: 'TRANSFER_OUT',
        onHandDelta: -quantity,
        reservedDelta: 0,
        unitCost: transferCost,
        landedCost: transferCost,
        occurredAt: occurredAt,
        note: note,
        skipAvailabilityCheck: true,
      );
      final outUuid = await _entityUuid(txn, 'inventory_movement', outId);
      final inId = await _recordMovementInTransaction(
        txn,
        itemId: itemId,
        warehouseId: toWarehouseId,
        movementType: 'TRANSFER_IN',
        onHandDelta: quantity,
        reservedDelta: 0,
        unitCost: transferCost,
        landedCost: transferCost,
        occurredAt: occurredAt,
        relatedMovementUuid: outUuid,
        note: note,
        skipAvailabilityCheck: true,
      );
      return [outId, inId];
    });
  }

  static Future<int> reverseMovement(
    int localMovementId, {
    String? note,
  }) async {
    final db = await _database;
    return SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn.query(
        InventoryTables.movements,
        where: 'id=?',
        whereArgs: [localMovementId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('INVENTORY_MOVEMENT_NOT_FOUND');
      final original = rows.single;
      final originalUuid = await _entityUuid(
        txn,
        'inventory_movement',
        localMovementId,
      );
      final reversed = await txn.query(
        InventoryTables.movements,
        where: "movement_type='REVERSAL' AND related_movement_uuid=?",
        whereArgs: [originalUuid],
        limit: 1,
      );
      if (reversed.isNotEmpty) {
        throw StateError('INVENTORY_MOVEMENT_ALREADY_REVERSED');
      }
      return _recordMovementInTransaction(
        txn,
        itemId: (original['item_id'] as num).toInt(),
        warehouseId: (original['warehouse_id'] as num).toInt(),
        movementType: 'REVERSAL',
        onHandDelta: -((original['on_hand_delta'] as num).toDouble()),
        reservedDelta: -((original['reserved_delta'] as num).toDouble()),
        unitCost: (original['unit_cost'] as num?)?.toDouble(),
        landedCost: (original['landed_cost'] as num?)?.toDouble(),
        currencyCode: original['currency_code']?.toString(),
        sourceEntityType: 'INVENTORY_REVERSAL',
        sourceReference: originalUuid,
        relatedMovementUuid: originalUuid,
        note: _nullable(note) ?? 'Reversal of immutable inventory movement.',
        skipAvailabilityCheck: false,
      );
    });
  }

  static Future<InventoryStockBalance> stockBalance({
    required int itemId,
    required int warehouseId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _database;
    return _stockBalance(db, itemId, warehouseId);
  }

  static Future<int> _recordMovementInTransaction(
    Transaction txn, {
    required int itemId,
    required int warehouseId,
    required String movementType,
    required double onHandDelta,
    required double reservedDelta,
    double? unitCost,
    double? landedCost,
    String? currencyCode,
    String? sourceEntityType,
    String? sourceEntityUuid,
    String? sourceReference,
    String? relatedMovementUuid,
    DateTime? occurredAt,
    String? note,
    bool skipAvailabilityCheck = false,
  }) async {
    _validateMovement(
      movementType,
      onHandDelta: onHandDelta,
      reservedDelta: reservedDelta,
      allowOpening: true,
    );
    if (!skipAvailabilityCheck) {
      if (reservedDelta > 0) {
        await _assertAvailable(txn, itemId, warehouseId, reservedDelta);
      }
      if (onHandDelta < 0) {
        await _assertAvailable(txn, itemId, warehouseId, -onHandDelta);
      }
      if (reservedDelta < 0) {
        final balance = await _stockBalance(txn, itemId, warehouseId);
        if (balance.reserved + reservedDelta < -0.000001) {
          throw StateError('INVENTORY_RELEASE_EXCEEDS_RESERVED');
        }
      }
    }
    final itemUuid = await _publishableUuid(
      txn,
      table: InventoryTables.items,
      entityType: 'inventory_item',
      localId: itemId,
    );
    final warehouseUuid = await _publishableUuid(
      txn,
      table: InventoryTables.warehouses,
      entityType: 'inventory_warehouse',
      localId: warehouseId,
    );
    final now = _now();
    return txn.insert(InventoryTables.movements, {
      'item_id': itemId,
      'item_entity_uuid': itemUuid,
      'warehouse_id': warehouseId,
      'warehouse_entity_uuid': warehouseUuid,
      'movement_type': movementType,
      'on_hand_delta': onHandDelta,
      'reserved_delta': reservedDelta,
      'unit_cost': unitCost,
      'landed_cost': landedCost,
      'currency_code': _nullable(currencyCode),
      'source_entity_type': _nullable(sourceEntityType),
      'source_entity_uuid': _nullable(sourceEntityUuid),
      'source_reference': _nullable(sourceReference),
      'related_movement_uuid': _nullable(relatedMovementUuid),
      'occurred_at': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
      'note': _nullable(note),
      'created_at': now,
    });
  }

  static Future<double> _weightedAverageUnitCost(
    DatabaseExecutor db, {
    required int itemId,
    required int warehouseId,
  }) async {
    final itemRows = await db.query(
      InventoryTables.items,
      columns: const ['default_purchase_price'],
      where: 'id=?',
      whereArgs: [itemId],
      limit: 1,
    );
    final fallback = itemRows.isEmpty
        ? 0.0
        : (itemRows.single['default_purchase_price'] as num?)?.toDouble() ??
            0.0;
    final rows = await db.query(
      InventoryTables.movements,
      columns: const [
        'on_hand_delta',
        'unit_cost',
        'landed_cost',
        'occurred_at',
        'id',
      ],
      where: 'item_id=? AND warehouse_id=?',
      whereArgs: [itemId, warehouseId],
      orderBy: 'datetime(occurred_at) ASC, id ASC',
    );
    var onHand = 0.0;
    var value = 0.0;
    for (final row in rows) {
      final delta = (row['on_hand_delta'] as num?)?.toDouble() ?? 0.0;
      if (delta == 0) continue;
      final currentAverage = onHand.abs() <= 0.000001 ? 0.0 : value / onHand;
      var cost = (row['landed_cost'] as num?)?.toDouble() ??
          (row['unit_cost'] as num?)?.toDouble();
      cost ??= currentAverage > 0 ? currentAverage : fallback;
      onHand += delta;
      value += delta * cost;
      if (onHand.abs() <= 0.000001) {
        onHand = 0.0;
        value = 0.0;
      }
      if (onHand < -0.000001) {
        throw StateError('INVENTORY_NEGATIVE_STOCK_LEDGER');
      }
    }
    if (onHand <= 0.000001) {
      return fallback;
    }
    return value / onHand;
  }

  static Future<void> _assertAvailable(
    DatabaseExecutor db,
    int itemId,
    int warehouseId,
    double required,
  ) async {
    final balance = await _stockBalance(db, itemId, warehouseId);
    if (balance.available + 0.000001 < required) {
      throw StateError('INVENTORY_INSUFFICIENT_AVAILABLE_STOCK');
    }
  }

  static Future<InventoryStockBalance> _stockBalance(
    DatabaseExecutor db,
    int itemId,
    int warehouseId,
  ) async {
    final rows = await db.query(
      InventoryTables.stockByWarehouseView,
      columns: const ['on_hand', 'reserved', 'available'],
      where: 'item_id=? AND warehouse_id=?',
      whereArgs: [itemId, warehouseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const InventoryStockBalance(onHand: 0, reserved: 0, available: 0);
    }
    final row = rows.single;
    return InventoryStockBalance(
      onHand: (row['on_hand'] as num?)?.toDouble() ?? 0,
      reserved: (row['reserved'] as num?)?.toDouble() ?? 0,
      available: (row['available'] as num?)?.toDouble() ?? 0,
    );
  }

  static Future<String> _publishableUuid(
    Transaction txn, {
    required String table,
    required String entityType,
    required int localId,
  }) async {
    var identity = await _identityForLocal(txn, entityType, localId);
    if (identity == null) throw StateError('INVENTORY_SYNC_IDENTITY_MISSING');
    if (((identity['revision'] as num?)?.toInt() ?? 0) == 0) {
      final changed = await txn.update(
        table,
        {'updated_at': _now()},
        where: 'id=?',
        whereArgs: [localId],
      );
      if (changed != 1) throw StateError('INVENTORY_REFERENCE_NOT_FOUND');
      identity = await _identityForLocal(txn, entityType, localId);
    }
    final uuid = identity?['entity_uuid']?.toString();
    if (uuid == null || uuid.length != 36) {
      throw StateError('INVENTORY_SYNC_IDENTITY_MISSING');
    }
    return uuid;
  }

  static Future<Map<String, Object?>?> _identityForLocal(
    DatabaseExecutor db,
    String entityType,
    int localId,
  ) async {
    final rows = await db.query(
      SyncFoundationTables.registry,
      where: 'entity_type=? AND local_id=?',
      whereArgs: [entityType, localId.toString()],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  static Future<String> _entityUuid(
    DatabaseExecutor db,
    String entityType,
    int localId,
  ) async {
    final identity = await _identityForLocal(db, entityType, localId);
    final uuid = identity?['entity_uuid']?.toString();
    if (uuid == null) throw StateError('INVENTORY_SYNC_IDENTITY_MISSING');
    return uuid;
  }

  static void _validateMovement(
    String type, {
    required double onHandDelta,
    required double reservedDelta,
    bool allowOpening = false,
  }) {
    if (!InventoryTables.movementTypes.contains(type)) {
      throw ArgumentError.value(type, 'movementType');
    }
    if (type == 'OPENING_BALANCE' && !allowOpening) {
      throw ArgumentError(
        'Opening balances are reserved for migration/import.',
      );
    }
    if (!onHandDelta.isFinite || !reservedDelta.isFinite) {
      throw ArgumentError('Inventory movement deltas must be finite.');
    }
    if (onHandDelta == 0 && reservedDelta == 0) {
      throw ArgumentError(
        'Inventory movement must change stock or reservation.',
      );
    }
    const inbound = {
      'PURCHASE_RECEIPT',
      'RETURN_IN',
      'DISMANTLED_ALLOCATION',
      'TRANSFER_IN',
      'WARRANTY_IN',
      'OPENING_BALANCE',
    };
    const outbound = {'SALE', 'RETURN_OUT', 'TRANSFER_OUT', 'WARRANTY_OUT'};
    if (inbound.contains(type) && !(onHandDelta > 0 && reservedDelta == 0)) {
      throw ArgumentError('Inbound stock movement must increase on-hand only.');
    }
    if (outbound.contains(type) && !(onHandDelta < 0 && reservedDelta == 0)) {
      throw ArgumentError(
        'Outbound stock movement must decrease on-hand only.',
      );
    }
    if (type == 'RESERVATION' && !(onHandDelta == 0 && reservedDelta > 0)) {
      throw ArgumentError('Reservation must increase reserved stock only.');
    }
    if (type == 'RELEASE' && !(onHandDelta == 0 && reservedDelta < 0)) {
      throw ArgumentError('Release must decrease reserved stock only.');
    }
    if (type == 'ADJUSTMENT' && reservedDelta != 0) {
      throw ArgumentError('Adjustment cannot mutate reserved stock.');
    }
  }

  static String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
