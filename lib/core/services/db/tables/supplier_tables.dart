// -----------------------------------------------------------------------------
// 📁 lib/core/services/db/tables/supplier_tables.dart
// Supplier schema: additive upgrades preserve contact details and account links.
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
    final columns = (await db.rawQuery('PRAGMA table_info(suppliers)'))
        .map((r) => r['name'])
        .toSet();
    for (final entry in {
      'pid': 'TEXT',
      'phone': 'TEXT',
      'address': 'TEXT',
      'account_id': 'INTEGER'
    }.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
            'ALTER TABLE suppliers ADD COLUMN ${entry.key} ${entry.value}');
      }
    }
    await db.execute(
        "UPDATE suppliers SET pid='S' || printf('%04d',id) WHERE pid IS NULL OR TRIM(pid)=''");
    debugPrint('Supplier contact details and account links preserved');
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
