import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/inventory_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Phase 10 v81 to v82 migrates legacy stock once without outbound noise',
      () async {
    final root = await Directory.systemTemp.createTemp('phase10_v82_');
    final path = '${root.path}/fixture.sqlite';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      expect(DatabaseConstants.dbVersion, 82);
      await db.insert('raw_materials', {
        'name': 'Primer',
        'supplier': 'Supplier A',
        'quantity': 7.5,
        'unit_price': 42.0,
        'description': 'legacy stock',
      });
      await db.execute(
          'DROP VIEW IF EXISTS ${InventoryTables.stockByWarehouseView}');
      await db
          .execute('DROP VIEW IF EXISTS ${InventoryTables.stockByItemView}');
      await db.execute('DROP TABLE IF EXISTS ${InventoryTables.alternatives}');
      await db.execute('DROP TABLE IF EXISTS ${InventoryTables.compatibility}');
      await db.execute('DROP TABLE IF EXISTS ${InventoryTables.movements}');
      await db.execute('DROP TABLE IF EXISTS ${InventoryTables.warehouses}');
      await db.execute('DROP TABLE IF EXISTS ${InventoryTables.items}');
      await db.delete('schema_migrations', where: 'version=?', whereArgs: [82]);
      await db.setVersion(81);
      await db.close();

      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), 82);
      expect(
          await db
              .query('schema_migrations', where: 'version=?', whereArgs: [82]),
          hasLength(1));

      final item = (await db.query(
        InventoryTables.items,
        where: 'legacy_source=? AND legacy_source_id=?',
        whereArgs: ['RAW_MATERIAL', '1'],
      ))
          .single;
      expect(item['name'], 'Primer');
      expect(item['item_kind'], 'RAW_MATERIAL');
      final warehouse = (await db.query(
        InventoryTables.warehouses,
        where: 'code=?',
        whereArgs: ['LEGACY-MAIN'],
      ))
          .single;
      final movement = (await db.query(
        InventoryTables.movements,
        where: 'source_entity_type=? AND source_reference=?',
        whereArgs: ['MIGRATION_V82', 'RAW_MATERIAL:1'],
      ))
          .single;
      expect(movement['on_hand_delta'], 7.5);
      expect(movement['warehouse_id'], warehouse['id']);

      final stock = (await db.query(
        InventoryTables.stockByWarehouseView,
        where: 'item_id=? AND warehouse_id=?',
        whereArgs: [item['id'], warehouse['id']],
      ))
          .single;
      expect(stock['on_hand'], 7.5);
      expect(stock['available'], 7.5);

      final inventoryOutbox = await db.query(
        UnifiedSyncTables.outbox,
        where: "entity_type LIKE 'inventory_%'",
      );
      expect(inventoryOutbox, isEmpty);
      await db.close();
      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(
        await db.query(
          InventoryTables.movements,
          where: 'source_entity_type=? AND source_reference=?',
          whereArgs: ['MIGRATION_V82', 'RAW_MATERIAL:1'],
        ),
        hasLength(1),
      );
      expect((await db.query('raw_materials')).single['quantity'], 7.5);
    } finally {
      if (db.isOpen) await db.close();
      DatabaseMigration.useDatabaseForTesting(null);
      await root.delete(recursive: true);
    }
  });
}
