// -----------------------------------------------------------------------------
// 📁 lib/core/services/db/tables/supplier_tables.dart
// FINAL — Simplified Supplier System
// ✔ suppliers(id, name)
// ✔ pid = printf("S%04d", id) (runtime only)
// ✔ فهارس جاهزة
// ✔ بدون phone / address / account_id / types
// ✔ مورد واحد فقط — بدون تصنيفات
// -----------------------------------------------------------------------------

import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

class SupplierTables {
  // ===========================================================================
  // CREATE ALL TABLES
  // ===========================================================================
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createSuppliersTable(db);
    await ensureSuppliersSchema(db);
  }

  // ===========================================================================
  // suppliers(id, name)
  // ===========================================================================
  static Future<void> _createSuppliersTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(LOWER(name));',
    );
  }

  // ===========================================================================
  // SCHEMA CLEANUP
  // ===========================================================================
  static Future<void> ensureSuppliersSchema(DatabaseExecutor db) async {
    await _dropColumnIfExists(db, 'suppliers', 'pid');
    await _dropColumnIfExists(db, 'suppliers', 'phone');
    await _dropColumnIfExists(db, 'suppliers', 'address');
    await _dropColumnIfExists(db, 'suppliers', 'account_id');
    await _dropColumnIfExists(db, 'suppliers', 'type');
    await _dropColumnIfExists(db, 'suppliers', 'category');

    debugPrint("✔ Supplier table normalized → (id, name)");
  }

  // ===========================================================================
  // SAFE DROP COLUMN
  // ===========================================================================
  static Future<void> _dropColumnIfExists(
      DatabaseExecutor db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((c) => c['name'] == column);
    if (!exists) return;

    final cols =
        info.where((c) => c['name'] != column).map((c) => c['name']).toList();

    final colsJoin = cols.join(', ');

    await db.execute('ALTER TABLE $table RENAME TO ${table}_old;');
    await db.execute('''
      CREATE TABLE $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      );
    ''');
    await db.execute(
      'INSERT INTO $table($colsJoin) SELECT $colsJoin FROM ${table}_old;',
    );
    await db.execute('DROP TABLE ${table}_old;');

    debugPrint("🛠 Removed column '$column' from $table");
  }

  // ===========================================================================
  // API — GET ALL SUPPLIERS
  // ===========================================================================
  static Future<List<Map<String, dynamic>>> getSuppliers(
      DatabaseExecutor db) async {
    return await db.rawQuery('''
      SELECT 
        id,
        name,
        printf("S%04d", id) AS pid
      FROM suppliers 
      ORDER BY name ASC
    ''');
  }

  static Future<Map<String, dynamic>?> getSupplierById(
      DatabaseExecutor db, int id) async {
    final r = await db.rawQuery(
      '''
        SELECT id, name, printf("S%04d", id) AS pid
        FROM suppliers 
        WHERE id = ? 
        LIMIT 1
      ''',
      [id],
    );
    return r.isNotEmpty ? r.first : null;
  }

  static Future<Map<String, dynamic>?> getSupplierByPid(
      DatabaseExecutor db, String pid) async {
    final r = await db.rawQuery(
      '''
        SELECT id, name, printf("S%04d", id) AS pid
        FROM suppliers 
        WHERE printf("S%04d", id) = ?
        LIMIT 1
      ''',
      [pid],
    );
    return r.isNotEmpty ? r.first : null;
  }

  // ===========================================================================
  // DEFAULT SUPPLIER (اختياري)
  // ===========================================================================
  static Future<void> ensureGeneralSupplier(DatabaseExecutor db) async {
    final r = await db.rawQuery(
      'SELECT id FROM suppliers WHERE name = "المصاريف العامة" LIMIT 1',
    );

    if (r.isNotEmpty) return;

    await db.insert('suppliers', {'name': 'المصاريف العامة'});
    debugPrint("✔ Created default supplier: المصاريف العامة (S0000)");
  }
}
