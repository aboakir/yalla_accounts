import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/accounting_gl.dart';
import 'package:yalla_accounts/core/services/db/tables/inventory_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/inventory/services/canonical_inventory_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';

class InventoryValuation {
  const InventoryValuation({
    required this.onHand,
    required this.stockValue,
    required this.averageUnitCost,
  });

  final double onHand;
  final double stockValue;
  final double averageUnitCost;
}

class InventoryStockCardRow {
  const InventoryStockCardRow({
    required this.movementId,
    required this.movementType,
    required this.quantityDelta,
    required this.unitCost,
    required this.runningOnHand,
    required this.runningValue,
    required this.occurredAt,
    this.sourceReference,
  });

  final int movementId;
  final String movementType;
  final double quantityDelta;
  final double unitCost;
  final double runningOnHand;
  final double runningValue;
  final DateTime occurredAt;
  final String? sourceReference;
}

class InventoryReorderStatus {
  const InventoryReorderStatus({
    required this.onHand,
    required this.available,
    required this.reorderLevel,
    required this.needsReorder,
  });

  final double onHand;
  final double available;
  final double reorderLevel;
  final bool needsReorder;
}

class InventoryRepairIssueResult {
  const InventoryRepairIssueResult({
    required this.issueId,
    required this.movementId,
    required this.costEntryId,
    required this.quantity,
    required this.unitCost,
  });

  final String issueId;
  final int movementId;
  final String costEntryId;
  final double quantity;
  final double unitCost;
}

class InventoryOperationsService {
  InventoryOperationsService._();

  static const _uuid = Uuid();
  static const _unitTable = 'inventory_unit_conversions';
  static const _reorderTable = 'inventory_reorder_levels';
  static const _issueTable = 'inventory_repair_issues';
  static const _returnTable = 'inventory_repair_returns';

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));
  static double _round6(double value) => double.parse(value.toStringAsFixed(6));

  static Future<void> ensureOperationalTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_unitTable(
        item_id INTEGER NOT NULL,
        unit TEXT NOT NULL,
        factor_to_base REAL NOT NULL CHECK(factor_to_base > 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(item_id, unit)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_reorderTable(
        item_id INTEGER NOT NULL,
        warehouse_id INTEGER NOT NULL,
        reorder_level REAL NOT NULL CHECK(reorder_level >= 0),
        updated_at TEXT NOT NULL,
        PRIMARY KEY(item_id, warehouse_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_issueTable(
        id TEXT PRIMARY KEY,
        repair_id TEXT NOT NULL,
        item_id INTEGER NOT NULL,
        warehouse_id INTEGER NOT NULL,
        movement_id INTEGER NOT NULL,
        cost_entry_id TEXT NOT NULL,
        gl_entry_id INTEGER NOT NULL,
        quantity_issued REAL NOT NULL CHECK(quantity_issued > 0),
        quantity_returned REAL NOT NULL DEFAULT 0 CHECK(quantity_returned >= 0),
        unit_cost REAL NOT NULL CHECK(unit_cost >= 0),
        cost_type TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_returnTable(
        id TEXT PRIMARY KEY,
        issue_id TEXT NOT NULL,
        movement_id INTEGER NOT NULL,
        cost_entry_id TEXT NOT NULL,
        gl_entry_id INTEGER NOT NULL,
        quantity REAL NOT NULL CHECK(quantity > 0),
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> setUnitConversion({
    required int itemId,
    required String unit,
    required double factorToBase,
  }) async {
    if (!factorToBase.isFinite || factorToBase <= 0) {
      throw ArgumentError.value(factorToBase, 'factorToBase');
    }
    final clean = unit.trim().toLowerCase();
    if (clean.isEmpty) throw ArgumentError.value(unit, 'unit');
    final db = await DBService.database;
    await ensureOperationalTables(db);
    await _itemRow(db, itemId);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      _unitTable,
      {
        'item_id': itemId,
        'unit': clean,
        'factor_to_base': factorToBase,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<double> convertToBase({
    required int itemId,
    required double quantity,
    required String unit,
  }) async {
    final db = await DBService.database;
    return convertToBaseOn(
      db,
      itemId: itemId,
      quantity: quantity,
      unit: unit,
    );
  }

  static Future<double> convertToBaseOn(
    DatabaseExecutor db, {
    required int itemId,
    required double quantity,
    required String unit,
  }) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity');
    }
    await ensureOperationalTables(db);
    final item = await _itemRow(db, itemId);
    final base = (item['unit']?.toString() ?? 'pcs').trim().toLowerCase();
    final clean = unit.trim().toLowerCase();
    if (clean.isEmpty || clean == base) return quantity;
    final rows = await db.query(
      _unitTable,
      columns: const ['factor_to_base'],
      where: 'item_id=? AND unit=?',
      whereArgs: [itemId, clean],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('INVENTORY_UNIT_CONVERSION_MISSING');
    }
    return quantity * (rows.single['factor_to_base'] as num).toDouble();
  }

  static Future<int> receivePurchaseLineOn(
    Transaction tx, {
    required int itemId,
    required int warehouseId,
    required double quantity,
    required double unitCost,
    required String purchaseLineId,
    String unit = '',
    String? currencyCode,
    DateTime? occurredAt,
  }) async {
    await ensureOperationalTables(tx);
    final existing = await tx.query(
      InventoryTables.movements,
      columns: const ['id'],
      where: 'source_entity_type=? AND source_reference=?',
      whereArgs: ['PURCHASE_LINE_RECEIPT', purchaseLineId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return (existing.single['id'] as num).toInt();
    }
    final item = await _itemRow(tx, itemId);
    final baseUnit = item['unit']?.toString() ?? 'pcs';
    final usedUnit = unit.trim().isEmpty ? baseUnit : unit;
    final factorQty = await convertToBaseOn(
      tx,
      itemId: itemId,
      quantity: quantity,
      unit: usedUnit,
    );
    final factor = factorQty / quantity;
    final baseUnitCost = unitCost / factor;
    return CanonicalInventoryService.recordMovementOn(
      tx,
      itemId: itemId,
      warehouseId: warehouseId,
      movementType: 'PURCHASE_RECEIPT',
      onHandDelta: factorQty,
      unitCost: baseUnitCost,
      landedCost: baseUnitCost,
      currencyCode: currencyCode,
      sourceEntityType: 'PURCHASE_LINE_RECEIPT',
      sourceReference: purchaseLineId,
      occurredAt: occurredAt,
      note: 'Stock receipt from purchase line $purchaseLineId',
    );
  }

  static Future<InventoryValuation> valuation({
    required int itemId,
    required int warehouseId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    await ensureOperationalTables(db);
    return _valuationOn(db, itemId: itemId, warehouseId: warehouseId);
  }

  static Future<InventoryValuation> _valuationOn(
    DatabaseExecutor db, {
    required int itemId,
    required int warehouseId,
  }) async {
    final item = await _itemRow(db, itemId);
    final fallback =
        (item['default_purchase_price'] as num?)?.toDouble() ?? 0.0;
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
        onHand = 0;
        value = 0;
      }
      if (onHand < -0.000001) {
        throw StateError('INVENTORY_NEGATIVE_STOCK_LEDGER');
      }
    }
    final average = onHand.abs() <= 0.000001 ? 0.0 : value / onHand;
    return InventoryValuation(
      onHand: _round6(onHand),
      stockValue: _round2(value),
      averageUnitCost: _round6(average),
    );
  }

  static Future<List<InventoryStockCardRow>> stockCard({
    required int itemId,
    required int warehouseId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    await ensureOperationalTables(db);
    final item = await _itemRow(db, itemId);
    final fallback =
        (item['default_purchase_price'] as num?)?.toDouble() ?? 0.0;
    final rows = await db.query(
      InventoryTables.movements,
      where: 'item_id=? AND warehouse_id=?',
      whereArgs: [itemId, warehouseId],
      orderBy: 'datetime(occurred_at) ASC, id ASC',
    );
    var onHand = 0.0;
    var value = 0.0;
    final out = <InventoryStockCardRow>[];
    for (final row in rows) {
      final delta = (row['on_hand_delta'] as num?)?.toDouble() ?? 0.0;
      final currentAverage = onHand.abs() <= 0.000001 ? 0.0 : value / onHand;
      var cost = (row['landed_cost'] as num?)?.toDouble() ??
          (row['unit_cost'] as num?)?.toDouble();
      cost ??= currentAverage > 0 ? currentAverage : fallback;
      onHand += delta;
      value += delta * cost;
      if (onHand.abs() <= 0.000001) {
        onHand = 0;
        value = 0;
      }
      out.add(InventoryStockCardRow(
        movementId: (row['id'] as num).toInt(),
        movementType: row['movement_type']?.toString() ?? '',
        quantityDelta: _round6(delta),
        unitCost: _round6(cost),
        runningOnHand: _round6(onHand),
        runningValue: _round2(value),
        occurredAt: DateTime.tryParse(row['occurred_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        sourceReference: row['source_reference']?.toString(),
      ));
    }
    return out;
  }

  static Future<InventoryRepairIssueResult> issueToRepair({
    required String operationId,
    required String repairId,
    required int itemId,
    required int warehouseId,
    required double quantity,
    required String costType,
    String? unit,
    String? note,
    bool faultAfterMovementForTesting = false,
  }) async {
    final db = await DBService.database;
    await ensureOperationalTables(db);
    await RepairCostService.ensureSchema(db);
    return SyncFoundationService.transaction(db, (tx) async {
      final existing =
          await tx.query(_issueTable, where: 'id=?', whereArgs: [operationId]);
      if (existing.isNotEmpty) {
        final row = existing.single;
        final same = row['repair_id'] == repairId &&
            (row['item_id'] as num).toInt() == itemId &&
            (row['warehouse_id'] as num).toInt() == warehouseId &&
            ((row['quantity_issued'] as num).toDouble() - quantity).abs() <
                0.000001;
        if (!same) throw StateError('INVENTORY_OPERATION_ID_REUSED');
        return InventoryRepairIssueResult(
          issueId: operationId,
          movementId: (row['movement_id'] as num).toInt(),
          costEntryId: row['cost_entry_id'].toString(),
          quantity: (row['quantity_issued'] as num).toDouble(),
          unitCost: (row['unit_cost'] as num).toDouble(),
        );
      }

      await _assertRepair(tx, repairId);
      final item = await _itemRow(tx, itemId);
      final baseUnit = item['unit']?.toString() ?? 'pcs';
      final baseQty = await convertToBaseOn(
        tx,
        itemId: itemId,
        quantity: quantity,
        unit: unit?.trim().isNotEmpty == true ? unit! : baseUnit,
      );
      final before =
          await _valuationOn(tx, itemId: itemId, warehouseId: warehouseId);
      if (before.onHand + 0.000001 < baseQty) {
        throw StateError('INVENTORY_INSUFFICIENT_AVAILABLE_STOCK');
      }
      if (before.averageUnitCost <= 0) {
        throw StateError('INVENTORY_COST_UNAVAILABLE');
      }
      final unitCost = before.averageUnitCost;
      final amount = _round2(baseQty * unitCost);
      final movementId = await CanonicalInventoryService.recordMovementOn(
        tx,
        itemId: itemId,
        warehouseId: warehouseId,
        movementType: 'SALE',
        onHandDelta: -baseQty,
        unitCost: unitCost,
        landedCost: unitCost,
        sourceEntityType: 'REPAIR_MATERIAL_ISSUE',
        sourceReference: operationId,
        note: note ?? 'Issued to repair $repairId',
      );
      if (faultAfterMovementForTesting) {
        throw StateError('INVENTORY_TEST_FAULT_AFTER_MOVEMENT');
      }

      final accounts = _accountsForItem(item);
      final glId = await _postInventoryGlOn(
        tx,
        source: 'INVENTORY_REPAIR_ISSUE',
        sourceId: operationId,
        date: DateTime.now(),
        debitCode: accounts.expense,
        creditCode: accounts.inventory,
        amount: amount,
        note: note ?? 'Material issued to repair $repairId',
        repairId: repairId,
      );

      final costEntryId = _uuid.v4();
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.insert('repair_cost_entries', {
        'id': costEntryId,
        'repair_id': repairId,
        'cost_type': costType,
        'item_name': item['name']?.toString() ?? 'Inventory item',
        'quantity_used': baseQty,
        'waste_quantity': 0.0,
        'unit_cost': unitCost,
        'total_cost': amount,
        'source_type': 'INVENTORY_ISSUE',
        'source_id': operationId,
        'note': note,
        'status': 'ACTIVE',
        'created_at': now,
        'created_by': 'INVENTORY',
      });
      await tx.insert(_issueTable, {
        'id': operationId,
        'repair_id': repairId,
        'item_id': itemId,
        'warehouse_id': warehouseId,
        'movement_id': movementId,
        'cost_entry_id': costEntryId,
        'gl_entry_id': glId,
        'quantity_issued': baseQty,
        'quantity_returned': 0.0,
        'unit_cost': unitCost,
        'cost_type': costType,
        'status': 'ACTIVE',
        'created_at': now,
        'updated_at': now,
      });
      return InventoryRepairIssueResult(
        issueId: operationId,
        movementId: movementId,
        costEntryId: costEntryId,
        quantity: baseQty,
        unitCost: unitCost,
      );
    });
  }

  static Future<int> returnFromRepair({
    required String operationId,
    required String issueId,
    required double quantity,
    String? note,
  }) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity');
    }
    final db = await DBService.database;
    await ensureOperationalTables(db);
    await RepairCostService.ensureSchema(db);
    return SyncFoundationService.transaction(db, (tx) async {
      final previous =
          await tx.query(_returnTable, where: 'id=?', whereArgs: [operationId]);
      if (previous.isNotEmpty) {
        return (previous.single['movement_id'] as num).toInt();
      }
      final rows =
          await tx.query(_issueTable, where: 'id=?', whereArgs: [issueId]);
      if (rows.isEmpty) throw StateError('INVENTORY_REPAIR_ISSUE_NOT_FOUND');
      final issue = rows.single;
      final issued = (issue['quantity_issued'] as num).toDouble();
      final returned = (issue['quantity_returned'] as num).toDouble();
      if (returned + quantity > issued + 0.000001) {
        throw StateError('INVENTORY_RETURN_EXCEEDS_ISSUED');
      }
      final itemId = (issue['item_id'] as num).toInt();
      final warehouseId = (issue['warehouse_id'] as num).toInt();
      final repairId = issue['repair_id'].toString();
      final unitCost = (issue['unit_cost'] as num).toDouble();
      final item = await _itemRow(tx, itemId);
      final amount = _round2(quantity * unitCost);
      final movementId = await CanonicalInventoryService.recordMovementOn(
        tx,
        itemId: itemId,
        warehouseId: warehouseId,
        movementType: 'RETURN_IN',
        onHandDelta: quantity,
        unitCost: unitCost,
        landedCost: unitCost,
        sourceEntityType: 'REPAIR_MATERIAL_RETURN',
        sourceReference: operationId,
        note: note ?? 'Returned from repair $repairId',
      );
      final accounts = _accountsForItem(item);
      final glId = await _postInventoryGlOn(
        tx,
        source: 'INVENTORY_REPAIR_RETURN',
        sourceId: operationId,
        date: DateTime.now(),
        debitCode: accounts.inventory,
        creditCode: accounts.expense,
        amount: amount,
        note: note ?? 'Material returned from repair $repairId',
        repairId: repairId,
      );
      final costEntryId = _uuid.v4();
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.insert('repair_cost_entries', {
        'id': costEntryId,
        'repair_id': repairId,
        'cost_type': issue['cost_type'],
        'item_name': item['name']?.toString() ?? 'Inventory item',
        'quantity_used': -quantity,
        'waste_quantity': 0.0,
        'unit_cost': unitCost,
        'total_cost': -amount,
        'source_type': 'INVENTORY_RETURN',
        'source_id': operationId,
        'note': note,
        'status': 'ACTIVE',
        'created_at': now,
        'created_by': 'INVENTORY',
      });
      await tx.insert(_returnTable, {
        'id': operationId,
        'issue_id': issueId,
        'movement_id': movementId,
        'cost_entry_id': costEntryId,
        'gl_entry_id': glId,
        'quantity': quantity,
        'created_at': now,
      });
      final nextReturned = returned + quantity;
      await tx.update(
        _issueTable,
        {
          'quantity_returned': nextReturned,
          'status': nextReturned >= issued - 0.000001 ? 'RETURNED' : 'ACTIVE',
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [issueId],
      );
      return movementId;
    });
  }

  static Future<int> damageStock({
    required String operationId,
    required int itemId,
    required int warehouseId,
    required double quantity,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw ArgumentError('Damage reason is required');
    return _adjustByDelta(
      operationId: operationId,
      itemId: itemId,
      warehouseId: warehouseId,
      delta: -quantity,
      sourceType: 'INVENTORY_DAMAGE',
      reason: reason,
    );
  }

  static Future<int> adjustToCount({
    required String operationId,
    required int itemId,
    required int warehouseId,
    required double countedOnHand,
    required String reason,
  }) async {
    if (!countedOnHand.isFinite || countedOnHand < 0) {
      throw ArgumentError.value(countedOnHand, 'countedOnHand');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('Inventory adjustment reason is required');
    }
    final current = await valuation(itemId: itemId, warehouseId: warehouseId);
    final delta = countedOnHand - current.onHand;
    if (delta.abs() <= 0.000001) {
      throw StateError('INVENTORY_ADJUSTMENT_NO_CHANGE');
    }
    return _adjustByDelta(
      operationId: operationId,
      itemId: itemId,
      warehouseId: warehouseId,
      delta: delta,
      sourceType: 'INVENTORY_COUNT_ADJUSTMENT',
      reason: reason,
    );
  }

  static Future<int> _adjustByDelta({
    required String operationId,
    required int itemId,
    required int warehouseId,
    required double delta,
    required String sourceType,
    required String reason,
  }) async {
    if (!delta.isFinite || delta == 0) {
      throw ArgumentError.value(delta, 'delta');
    }
    final db = await DBService.database;
    await ensureOperationalTables(db);
    return SyncFoundationService.transaction(db, (tx) async {
      final existing = await tx.query(
        InventoryTables.movements,
        columns: const ['id'],
        where: 'source_entity_type=? AND source_reference=?',
        whereArgs: [sourceType, operationId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return (existing.single['id'] as num).toInt();
      }
      final item = await _itemRow(tx, itemId);
      final before =
          await _valuationOn(tx, itemId: itemId, warehouseId: warehouseId);
      if (delta < 0 && before.onHand + delta < -0.000001) {
        throw StateError('INVENTORY_INSUFFICIENT_AVAILABLE_STOCK');
      }
      var unitCost = before.averageUnitCost;
      unitCost = unitCost > 0
          ? unitCost
          : (item['default_purchase_price'] as num?)?.toDouble() ?? 0.0;
      if (unitCost <= 0) throw StateError('INVENTORY_COST_UNAVAILABLE');
      final amount = _round2(delta.abs() * unitCost);
      final movementId = await CanonicalInventoryService.recordMovementOn(
        tx,
        itemId: itemId,
        warehouseId: warehouseId,
        movementType: 'ADJUSTMENT',
        onHandDelta: delta,
        unitCost: unitCost,
        landedCost: unitCost,
        sourceEntityType: sourceType,
        sourceReference: operationId,
        note: reason,
      );
      final accounts = _accountsForItem(item);
      await _postInventoryGlOn(
        tx,
        source: sourceType,
        sourceId: operationId,
        date: DateTime.now(),
        debitCode: delta > 0 ? accounts.inventory : GL.otherExpense,
        creditCode: delta > 0 ? GL.otherExpense : accounts.inventory,
        amount: amount,
        note: reason,
      );
      return movementId;
    });
  }

  static Future<List<int>> reversePurchaseReceiptsOn(
    Transaction tx, {
    required String purchaseInvoiceId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Inventory purchase reversal reason is required');
    }
    await ensureOperationalTables(tx);
    final lines = await tx.query(
      'purchase_invoice_lines',
      where:
          'invoice_id=? AND receive_stock=1 AND COALESCE(stock_received_qty,0)>0',
      whereArgs: [purchaseInvoiceId],
    );
    final reversals = <int>[];
    for (final line in lines) {
      reversals.add(await _reversePurchaseReceiptLineOn(
        tx,
        line: line,
        reason: reason,
      ));
    }
    return reversals;
  }

  static Future<void> setReorderLevel({
    required int itemId,
    required int warehouseId,
    required double level,
  }) async {
    if (!level.isFinite || level < 0) throw ArgumentError.value(level, 'level');
    final db = await DBService.database;
    await ensureOperationalTables(db);
    await _itemRow(db, itemId);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      _reorderTable,
      {
        'item_id': itemId,
        'warehouse_id': warehouseId,
        'reorder_level': level,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<InventoryReorderStatus> reorderStatus({
    required int itemId,
    required int warehouseId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    await ensureOperationalTables(db);
    final levelRows = await db.query(
      _reorderTable,
      columns: const ['reorder_level'],
      where: 'item_id=? AND warehouse_id=?',
      whereArgs: [itemId, warehouseId],
      limit: 1,
    );
    final level = levelRows.isEmpty
        ? 0.0
        : (levelRows.single['reorder_level'] as num).toDouble();
    final balance = await CanonicalInventoryService.stockBalance(
      itemId: itemId,
      warehouseId: warehouseId,
      executor: db,
    );
    return InventoryReorderStatus(
      onHand: balance.onHand,
      available: balance.available,
      reorderLevel: level,
      needsReorder: level > 0 && balance.available <= level + 0.000001,
    );
  }

  static Future<int> _reversePurchaseReceiptLineOn(
    Transaction tx, {
    required Map<String, Object?> line,
    required String reason,
  }) async {
    final lineId = line['id']?.toString() ?? '';
    final movementRows = await tx.query(
      InventoryTables.movements,
      where: 'source_entity_type=? AND source_reference=?',
      whereArgs: ['PURCHASE_LINE_RECEIPT', lineId],
      limit: 1,
    );
    if (movementRows.isEmpty) {
      throw StateError('INVENTORY_PURCHASE_RECEIPT_NOT_FOUND');
    }
    final movement = movementRows.single;
    final movementId = (movement['id'] as num).toInt();
    final identity = await InventoryTables.identityForLocal(
      tx,
      'inventory_movement',
      movementId,
    );
    final movementUuid = identity?['entity_uuid']?.toString();
    if (movementUuid == null || movementUuid.isEmpty) {
      throw StateError('INVENTORY_PURCHASE_RECEIPT_IDENTITY_MISSING');
    }
    final prior = await tx.query(
      InventoryTables.movements,
      columns: const ['id'],
      where: "movement_type='REVERSAL' AND related_movement_uuid=?",
      whereArgs: [movementUuid],
      limit: 1,
    );
    if (prior.isNotEmpty) {
      return (prior.single['id'] as num).toInt();
    }

    final itemId = (movement['item_id'] as num).toInt();
    final warehouseId = (movement['warehouse_id'] as num).toInt();
    final qty = (movement['on_hand_delta'] as num).toDouble();
    final balanceRows = await tx.query(
      InventoryTables.stockByWarehouseView,
      columns: const ['available'],
      where: 'item_id=? AND warehouse_id=?',
      whereArgs: [itemId, warehouseId],
      limit: 1,
    );
    final available = balanceRows.isEmpty
        ? 0.0
        : (balanceRows.single['available'] as num?)?.toDouble() ?? 0.0;
    if (qty <= 0 || available + 0.000001 < qty) {
      throw StateError('INVENTORY_PURCHASE_VOID_STOCK_ALREADY_CONSUMED');
    }

    return CanonicalInventoryService.recordMovementOn(
      tx,
      itemId: itemId,
      warehouseId: warehouseId,
      movementType: 'REVERSAL',
      onHandDelta: -qty,
      unitCost: (movement['unit_cost'] as num?)?.toDouble(),
      landedCost: (movement['landed_cost'] as num?)?.toDouble(),
      currencyCode: movement['currency_code']?.toString(),
      sourceEntityType: 'PURCHASE_RECEIPT_VOID',
      sourceReference: lineId,
      relatedMovementUuid: movementUuid,
      note: reason,
      skipAvailabilityCheck: true,
    );
  }

  static Future<Map<String, Object?>> _itemRow(
    DatabaseExecutor db,
    int itemId,
  ) async {
    final rows = await db.query(
      InventoryTables.items,
      where: 'id=?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('INVENTORY_ITEM_NOT_FOUND');
    return Map<String, Object?>.from(rows.single);
  }

  static Future<void> _assertRepair(
    DatabaseExecutor db,
    String repairId,
  ) async {
    final rows = await db.query(
      'repairs',
      columns: const ['id'],
      where: 'id=?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('REPAIR_NOT_FOUND');
  }

  static _InventoryAccounts _accountsForItem(Map<String, Object?> item) {
    final kind = (item['item_kind']?.toString() ?? 'OTHER').toUpperCase();
    if (kind == 'PART') {
      return const _InventoryAccounts(
        inventory: GL.partsInventory,
        expense: GL.purchasesExpense,
      );
    }
    if (kind == 'RAW_MATERIAL') {
      return const _InventoryAccounts(
        inventory: GL.inventoryOrPurchases,
        expense: GL.rawMaterialsExpense,
      );
    }
    return const _InventoryAccounts(
      inventory: GL.inventoryOrPurchases,
      expense: GL.otherExpense,
    );
  }

  static Future<int> _accountIdOn(
    DatabaseExecutor db,
    String code,
  ) async {
    final rows = await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('ACCOUNT_NOT_FOUND:$code');
    return (rows.single['id'] as num).toInt();
  }

  static Future<int> _postInventoryGlOn(
    DatabaseExecutor db, {
    required String source,
    required String sourceId,
    required DateTime date,
    required String debitCode,
    required String creditCode,
    required double amount,
    required String note,
    String? repairId,
  }) async {
    final debitId = await _accountIdOn(db, debitCode);
    final creditId = await _accountIdOn(db, creditCode);
    return DBService.postEntryGLOn(
      ex: db,
      date: date,
      ref: sourceId,
      source: source,
      sourceId: sourceId,
      note: note,
      lines: [
        {
          'account_id': debitId,
          'debit': amount,
          'credit': 0.0,
          if (repairId != null) 'repair_id': repairId,
        },
        {
          'account_id': creditId,
          'debit': 0.0,
          'credit': amount,
          if (repairId != null) 'repair_id': repairId,
        },
      ],
    );
  }
}

class _InventoryAccounts {
  const _InventoryAccounts({
    required this.inventory,
    required this.expense,
  });

  final String inventory;
  final String expense;
}
