import 'package:sqflite/sqflite.dart';

import 'sync_foundation_tables.dart';

/// Phase 10 canonical inventory schema.
///
/// Stock balances are never stored as authoritative columns. They are derived
/// from immutable movements so offline devices can exchange facts instead of
/// overwriting a final quantity.
class InventoryTables {
  InventoryTables._();

  static const items = 'inventory_items_master';
  static const warehouses = 'inventory_warehouses';
  static const movements = 'inventory_movements';
  static const alternatives = 'inventory_item_alternatives';
  static const compatibility = 'inventory_item_compatibility';
  static const stockByWarehouseView = 'inventory_stock_balances';
  static const stockByItemView = 'inventory_item_stock';

  static const movementTypes = <String>{
    'OPENING_BALANCE',
    'PURCHASE_RECEIPT',
    'SALE',
    'RETURN_IN',
    'RETURN_OUT',
    'RESERVATION',
    'RELEASE',
    'ADJUSTMENT',
    'DISMANTLED_ALLOCATION',
    'TRANSFER_IN',
    'TRANSFER_OUT',
    'WARRANTY_IN',
    'WARRANTY_OUT',
    'REVERSAL',
  };

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        legacy_source TEXT,
        legacy_source_id TEXT,
        name TEXT NOT NULL,
        sku TEXT,
        oem_number TEXT,
        barcode TEXT,
        item_kind TEXT NOT NULL DEFAULT 'PART'
          CHECK(item_kind IN ('PART','RAW_MATERIAL','TOOL','OTHER')),
        unit TEXT NOT NULL DEFAULT 'pcs',
        category TEXT,
        origin_country TEXT,
        supplier_name TEXT,
        default_purchase_price REAL,
        default_selling_price REAL,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(legacy_source, legacy_source_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_master_name ON $items(name)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_master_sku '
      'ON $items(sku) WHERE sku IS NOT NULL AND TRIM(sku)<>\'\'',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_master_barcode '
      'ON $items(barcode) WHERE barcode IS NOT NULL AND TRIM(barcode)<>\'\'',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $warehouses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        branch_code TEXT,
        location TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES $items(id),
        item_entity_uuid TEXT NOT NULL,
        warehouse_id INTEGER NOT NULL REFERENCES $warehouses(id),
        warehouse_entity_uuid TEXT NOT NULL,
        movement_type TEXT NOT NULL CHECK(movement_type IN (
          'OPENING_BALANCE','PURCHASE_RECEIPT','SALE','RETURN_IN','RETURN_OUT',
          'RESERVATION','RELEASE','ADJUSTMENT','DISMANTLED_ALLOCATION',
          'TRANSFER_IN','TRANSFER_OUT','WARRANTY_IN','WARRANTY_OUT','REVERSAL'
        )),
        on_hand_delta REAL NOT NULL DEFAULT 0,
        reserved_delta REAL NOT NULL DEFAULT 0,
        unit_cost REAL,
        landed_cost REAL,
        currency_code TEXT,
        source_entity_type TEXT,
        source_entity_uuid TEXT,
        source_reference TEXT,
        related_movement_uuid TEXT,
        occurred_at TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        CHECK(on_hand_delta<>0 OR reserved_delta<>0)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_movements_item_wh_time '
      'ON $movements(item_id,warehouse_id,occurred_at,id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_movements_item_uuid '
      'ON $movements(item_entity_uuid,warehouse_entity_uuid,occurred_at,id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_movement_source_once '
      'ON $movements(source_entity_type,source_reference) '
      'WHERE source_entity_type IS NOT NULL AND source_reference IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_reversal_once '
      'ON $movements(related_movement_uuid) '
      "WHERE movement_type='REVERSAL' AND related_movement_uuid IS NOT NULL",
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $alternatives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES $items(id),
        item_entity_uuid TEXT NOT NULL,
        alternative_item_id INTEGER NOT NULL REFERENCES $items(id),
        alternative_item_entity_uuid TEXT NOT NULL,
        note TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(item_id,alternative_item_id),
        CHECK(item_id<>alternative_item_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $compatibility (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES $items(id),
        item_entity_uuid TEXT NOT NULL,
        make TEXT,
        model TEXT,
        year_from INTEGER,
        year_to INTEGER,
        engine TEXT,
        body TEXT,
        note TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK(year_from IS NULL OR year_to IS NULL OR year_from<=year_to)
      )
    ''');

    await _installMovementImmutability(db);
    await _rebuildViews(db);
  }

  static Future<void> _installMovementImmutability(DatabaseExecutor db) async {
    for (final op in const ['UPDATE', 'DELETE']) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_inventory_movements_append_only_${op.toLowerCase()}
        BEFORE $op ON $movements
        BEGIN SELECT RAISE(ABORT,'INVENTORY_MOVEMENT_APPEND_ONLY'); END
      ''');
    }
  }

  static Future<void> _rebuildViews(DatabaseExecutor db) async {
    await db.execute('DROP VIEW IF EXISTS $stockByWarehouseView');
    await db.execute('''
      CREATE VIEW $stockByWarehouseView AS
      SELECT item_id,item_entity_uuid,warehouse_id,warehouse_entity_uuid,
             ROUND(COALESCE(SUM(on_hand_delta),0),6) AS on_hand,
             ROUND(COALESCE(SUM(reserved_delta),0),6) AS reserved,
             ROUND(COALESCE(SUM(on_hand_delta),0)-COALESCE(SUM(reserved_delta),0),6)
               AS available
      FROM $movements
      GROUP BY item_id,item_entity_uuid,warehouse_id,warehouse_entity_uuid
    ''');
    await db.execute('DROP VIEW IF EXISTS $stockByItemView');
    await db.execute('''
      CREATE VIEW $stockByItemView AS
      SELECT i.id AS item_id,r.entity_uuid AS item_entity_uuid,
             i.name,i.sku,i.oem_number,i.barcode,i.item_kind,i.unit,i.category,
             ROUND(COALESCE(SUM(m.on_hand_delta),0),6) AS on_hand,
             ROUND(COALESCE(SUM(m.reserved_delta),0),6) AS reserved,
             ROUND(COALESCE(SUM(m.on_hand_delta),0)-COALESCE(SUM(m.reserved_delta),0),6)
               AS available
      FROM $items i
      LEFT JOIN $movements m ON m.item_id=i.id
      LEFT JOIN ${SyncFoundationTables.registry} r
        ON r.entity_type='inventory_item' AND r.local_id=CAST(i.id AS TEXT)
      GROUP BY i.id,r.entity_uuid
    ''');
  }

  static Future<Map<String, Object?>?> identityForLocal(
    DatabaseExecutor db,
    String entityType,
    Object localId,
  ) async {
    final rows = await db.query(
      SyncFoundationTables.registry,
      where: 'entity_type=? AND local_id=?',
      whereArgs: [entityType, localId.toString()],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  /// Preserves historical local stock without fabricating outbound changes.
  /// Call while sync mutation context is remote during the v82 migration.
  static Future<void> backfillLegacyStock(DatabaseExecutor db) async {
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ))
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();

    if (!tables.contains('raw_materials') &&
        !tables.contains('inventory_items')) {
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    int? warehouseId;
    String? warehouseUuid;

    Future<void> ensureLegacyWarehouse() async {
      if (warehouseId != null) return;
      var rows = await db.query(
        warehouses,
        where: 'code=?',
        whereArgs: ['LEGACY-MAIN'],
        limit: 1,
      );
      if (rows.isEmpty) {
        await db.insert(warehouses, {
          'code': 'LEGACY-MAIN',
          'name': 'Legacy Main Warehouse',
          'location': 'Migrated local stock',
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        rows = await db.query(
          warehouses,
          where: 'code=?',
          whereArgs: ['LEGACY-MAIN'],
          limit: 1,
        );
      }
      warehouseId = (rows.single['id'] as num).toInt();
      final identity = await identityForLocal(
        db,
        'inventory_warehouse',
        warehouseId!,
      );
      warehouseUuid = identity?['entity_uuid']?.toString();
      if (warehouseUuid == null) {
        throw StateError('INVENTORY_MIGRATION_WAREHOUSE_IDENTITY_MISSING');
      }
    }

    Future<void> migrateRow({
      required String source,
      required Object sourceId,
      required String name,
      required String itemKind,
      String? sku,
      String? category,
      String? unit,
      String? supplierName,
      String? description,
      double? purchasePrice,
      double? sellingPrice,
      required double quantity,
    }) async {
      final sourceText = sourceId.toString();
      var itemRows = await db.query(
        items,
        where: 'legacy_source=? AND legacy_source_id=?',
        whereArgs: [source, sourceText],
        limit: 1,
      );
      if (itemRows.isEmpty) {
        await db.insert(items, {
          'legacy_source': source,
          'legacy_source_id': sourceText,
          'name': name,
          'sku': sku,
          'item_kind': itemKind,
          'unit': (unit == null || unit.trim().isEmpty) ? 'pcs' : unit.trim(),
          'category': category,
          'supplier_name': supplierName,
          'default_purchase_price': purchasePrice,
          'default_selling_price': sellingPrice,
          'description': description,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        itemRows = await db.query(
          items,
          where: 'legacy_source=? AND legacy_source_id=?',
          whereArgs: [source, sourceText],
          limit: 1,
        );
      }
      final itemId = (itemRows.single['id'] as num).toInt();
      final identity = await identityForLocal(db, 'inventory_item', itemId);
      final itemUuid = identity?['entity_uuid']?.toString();
      if (itemUuid == null) {
        throw StateError('INVENTORY_MIGRATION_ITEM_IDENTITY_MISSING');
      }
      if (quantity == 0) return;
      await ensureLegacyWarehouse();
      await db.insert(
          movements,
          {
            'item_id': itemId,
            'item_entity_uuid': itemUuid,
            'warehouse_id': warehouseId,
            'warehouse_entity_uuid': warehouseUuid,
            'movement_type': 'OPENING_BALANCE',
            'on_hand_delta': quantity,
            'reserved_delta': 0.0,
            'unit_cost': purchasePrice,
            'landed_cost': purchasePrice,
            'currency_code': null,
            'source_entity_type': 'MIGRATION_V82',
            'source_reference': '$source:$sourceText',
            'occurred_at': now,
            'note': 'Opening balance migrated from legacy local stock.',
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (tables.contains('raw_materials')) {
      final rows = await db.query('raw_materials');
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        await migrateRow(
          source: 'RAW_MATERIAL',
          sourceId: id,
          name: name,
          itemKind: 'RAW_MATERIAL',
          category: 'RAW_MATERIAL',
          supplierName: row['supplier']?.toString(),
          description: row['description']?.toString(),
          purchasePrice: (row['unit_price'] as num?)?.toDouble(),
          quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
        );
      }
    }

    if (tables.contains('inventory_items')) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(inventory_items)',
      ))
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();
      final rows = await db.query('inventory_items');
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final qtyKey = columns.contains('quantityInStock')
            ? 'quantityInStock'
            : columns.contains('quantity')
                ? 'quantity'
                : null;
        final purchaseKey = columns.contains('purchasePrice')
            ? 'purchasePrice'
            : columns.contains('unit_price')
                ? 'unit_price'
                : null;
        await migrateRow(
          source: 'INVENTORY_ITEM',
          sourceId: id,
          name: name,
          itemKind: 'PART',
          sku: columns.contains('partNumber')
              ? row['partNumber']?.toString()
              : null,
          category: row['category']?.toString(),
          unit: columns.contains('unit') ? row['unit']?.toString() : null,
          description: columns.contains('description')
              ? row['description']?.toString()
              : null,
          purchasePrice: purchaseKey == null
              ? null
              : (row[purchaseKey] as num?)?.toDouble(),
          sellingPrice: columns.contains('sellingPrice')
              ? (row['sellingPrice'] as num?)?.toDouble()
              : null,
          quantity:
              qtyKey == null ? 0.0 : (row[qtyKey] as num?)?.toDouble() ?? 0.0,
        );
      }
    }
  }
}
