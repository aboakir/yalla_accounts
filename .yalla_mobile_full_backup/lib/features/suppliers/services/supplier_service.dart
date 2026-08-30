// 📁 lib/features/suppliers/services/supplier_service.dart
//
// SupplierService — FINAL CLEAN VERSION (100% READY)

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/suppliers/models/supplier.dart';

class SupplierService {
  static const String tableName = 'suppliers';

  /// إنشاء جدول الموردين
  static Future<void> createTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS $tableName (
  id INTEGER PRIMARY KEY,
  pid TEXT,
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  account_id INTEGER
)
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON $tableName(LOWER(name));',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_account ON $tableName(account_id);',
    );
  }

  // ============================================================
  // INSERT
  // ============================================================
  static Future<String> insertSupplier(Supplier supplier) async {
    final db = await DBService.database;
    await createTable(db);

    final data = <String, Object?>{
      'name': supplier.name.trim(),
      'phone': supplier.phone,
      'address': supplier.address,
    };

    final int newId = await db.insert(
      tableName,
      data,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    // إنشاء PID
    await db.execute("""
UPDATE $tableName
SET pid = 'S' || printf('%04d', $tableName.id)
WHERE id = $newId AND (pid IS NULL OR TRIM(pid) = '');
""");

    // ربط الحساب
    try {
      final accId = await DBService.ensureSupplierAccount(newId.toString());
      await db.update(
        tableName,
        {'account_id': accId},
        where: 'id = ? AND (account_id IS NULL)',
        whereArgs: [newId],
      );
    } catch (_) {}

    return newId.toString();
  }

  // ============================================================
  // UPDATE
  // ============================================================
  static Future<int> updateSupplier(Supplier supplier) async {
    final db = await DBService.database;
    await createTable(db);

    final sid = supplier.id.trim();

    final data = <String, Object?>{
      'name': supplier.name.trim(),
      'phone': supplier.phone,
      'address': supplier.address,
    };

    final count = await db.update(
      tableName,
      data,
      where: 'id = ?',
      whereArgs: [sid],
    );

    // ربط الحساب إن مفقود
    try {
      final accId = await _getSupplierAccountId(sid);
      if (accId == null) {
        final ensured = await DBService.ensureSupplierAccount(sid);
        await db.update(
          tableName,
          {'account_id': ensured},
          where: 'id = ?',
          whereArgs: [sid],
        );
      }
    } catch (_) {}

    // ضمان PID
    await db.execute("""
UPDATE $tableName
SET pid = 'S' || printf('%04d', $tableName.id)
WHERE id = $sid AND (pid IS NULL OR TRIM(pid) = '');
""");

    return count;
  }

  // ============================================================
  // DELETE
  // ============================================================
  static Future<int> deleteSupplier(String pid) async {
    final db = await DBService.database;
    await createTable(db);
    return db.delete(
      tableName,
      where: 'pid = ?',
      whereArgs: [pid],
    );
  }

  // ============================================================
  // GET ALL
  // ============================================================
  static Future<List<Supplier>> getAllSuppliers() async {
    final db = await DBService.database;
    await createTable(db);

    final rows = await db.query(
      tableName,
      orderBy: 'name ASC',
      columns: ['id', 'pid', 'name', 'phone', 'address'],
    );

    return rows.map(Supplier.fromMap).toList();
  }

  // ============================================================
  // SEARCH
  // ============================================================
  static Future<List<Supplier>> search({
    String? query,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await DBService.database;
    await createTable(db);

    final where = <String>[];
    final args = <Object?>[];

    if (query != null && query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      where.add('(name LIKE ? OR phone LIKE ? OR address LIKE ?)');
      args
        ..add(like)
        ..add(like)
        ..add(like);
    }

    final rows = await db.query(
      tableName,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );

    return rows.map(Supplier.fromMap).toList();
  }

  // ============================================================
  // INSERT OR GET
  // ============================================================
  static Future<String> insertOrGetSupplierId(
    String name, {
    String? phone,
    String? address,
  }) async {
    final existing = await getSupplierIdByName(name);
    if (existing != null && existing.isNotEmpty) return existing;

    final db = await DBService.database;
    await createTable(db);

    final int newId = await db.insert(
      tableName,
      {
        'name': name.trim(),
        'phone': phone,
        'address': address,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    // PID واحد فقط
    await db.execute("""
UPDATE $tableName
SET pid = 'S' || printf('%04d', $tableName.id)
WHERE id = $newId AND (pid IS NULL OR TRIM(pid) = '');
""");

    try {
      final accId = await DBService.ensureSupplierAccount(newId.toString());
      await db.update(
        tableName,
        {'account_id': accId},
        where: 'id = ? AND (account_id IS NULL)',
        whereArgs: [newId],
      );
    } catch (_) {}

    return newId.toString();
  }

  // ============================================================
  // HELPERS
  // ============================================================
  static Future<String?> getSupplierIdByName(String name) async {
    final db = await DBService.database;
    await createTable(db);

    final r = await db.query(
      tableName,
      columns: const ['id'],
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [name.trim()],
      limit: 1,
    );

    if (r.isNotEmpty) return (r.first['id'] ?? '').toString();
    return null;
  }

  static Future<int> getTotalSuppliers() async {
    final db = await DBService.database;
    await createTable(db);
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  static Future<int> getOrEnsureAccountId(
      String supplierId, String supplierName) async {
    final acc = await _getSupplierAccountId(supplierId);
    if (acc != null) return acc;

    final ensured = await DBService.ensureSupplierAccount(supplierId);
    final db = await DBService.database;

    await db.update(
      tableName,
      {'account_id': ensured},
      where: 'id = ?',
      whereArgs: [supplierId],
    );

    return ensured;
  }

  static Future<int?> _getSupplierAccountId(String supplierId) async {
    final db = await DBService.database;

    final r = await db.query(
      tableName,
      columns: const ['account_id'],
      where: 'id = ?',
      whereArgs: [supplierId],
      limit: 1,
    );

    if (r.isEmpty) return null;

    final v = r.first['account_id'];
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
