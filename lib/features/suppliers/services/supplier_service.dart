import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
// 📁 lib/features/suppliers/services/supplier_service.dart
//
// SupplierService — FINAL CLEAN VERSION (100% READY)

import 'package:sqflite/sqflite.dart';
import '../../../core/services/db/tables/supplier_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/suppliers/models/supplier.dart';

class DuplicateSupplierException implements Exception {
  const DuplicateSupplierException(this.name);
  final String name;
  @override
  String toString() =>
      'المورد $name موجود مسبقًا؛ اختر السجل الموجود أو عدّل بياناته.';
}

class SupplierService {
  static String _identity(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static Future<String?> _duplicateOn(DatabaseExecutor db, String name,
      {String? excludeId}) async {
    final normalized = _identity(name);
    if (normalized.isEmpty) throw StateError('اسم المورد مطلوب');
    final rows = await db.query(tableName, columns: ['id', 'name']);
    for (final row in rows) {
      if ('${row['id']}' != excludeId &&
          _identity('${row['name'] ?? ''}') == normalized) {
        return '${row['id']}';
      }
    }
    return null;
  }

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

    await SupplierTables.ensureSuppliersSchema(db);

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

    final int newId = await SyncFoundationService.transaction(db, (tx) async {
      if (await _duplicateOn(tx, supplier.name) != null) {
        throw DuplicateSupplierException(supplier.name);
      }
      return tx.insert(tableName, data,
          conflictAlgorithm: ConflictAlgorithm.abort);
    });

    // إنشاء PID
    await db.execute("""
UPDATE $tableName
SET pid = 'S' || printf('%04d', $tableName.id)
WHERE id = $newId AND (pid IS NULL OR TRIM(pid) = '');
""");

    // ربط الحساب
    try {
      final accId = await DBService.ensureSupplierAccount(newId.toString());
      await SyncFoundationService.writeOn(
          db,
          (syncTxn) => syncTxn.update(
                tableName,
                {'account_id': accId},
                where: 'id = ? AND (account_id IS NULL)',
                whereArgs: [newId],
              ));
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
    if ((int.tryParse(sid) ?? 0) <= 0) throw StateError('رقم المورد غير صالح');

    final data = <String, Object?>{
      'name': supplier.name.trim(),
      'phone': supplier.phone,
      'address': supplier.address,
    };

    final count = await SyncFoundationService.transaction(db, (tx) async {
      if (await _duplicateOn(tx, supplier.name, excludeId: sid) != null) {
        throw DuplicateSupplierException(supplier.name);
      }
      return tx.update(tableName, data, where: 'id = ?', whereArgs: [sid]);
    });

    // ربط الحساب إن مفقود
    try {
      final accId = await _getSupplierAccountId(sid);
      if (accId == null) {
        final ensured = await DBService.ensureSupplierAccount(sid);
        await SyncFoundationService.writeOn(
            db,
            (syncTxn) => syncTxn.update(
                  tableName,
                  {'account_id': ensured},
                  where: 'id = ?',
                  whereArgs: [sid],
                ));
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
    return SyncFoundationService.transaction(db, (tx) async {
      final rows = await tx.query(tableName,
          where: 'pid = ? OR CAST(id AS TEXT) = ?', whereArgs: [pid, pid]);
      if (rows.isEmpty) return 0;
      final id = rows.single['id'];
      final linked = await tx.rawQuery("""
        SELECT 1 FROM purchase_invoices WHERE supplier_id=?
        UNION ALL SELECT 1 FROM vouchers WHERE UPPER(party_type)='SUPPLIER' AND (party_id=? OR party_id=?)
        UNION ALL SELECT 1 FROM gl_lines WHERE account_id=?
        LIMIT 1
      """, [id, '$id', rows.single['pid'], rows.single['account_id']]);
      if (linked.isNotEmpty) {
        throw StateError(
            'لا يمكن حذف مورد له مشتريات أو دفعات أو قيود. يمكنك تعديل بياناته.');
      }
      return tx.delete(tableName, where: 'id=?', whereArgs: [id]);
    });
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
    if (existing != null) return existing;
    try {
      return await insertSupplier(Supplier(
          id: '',
          pid: '',
          name: name,
          phone: phone ?? '',
          address: address ?? ''));
    } on DuplicateSupplierException {
      final id = await getSupplierIdByName(name);
      if (id != null) return id;
      rethrow;
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================
  static Future<String?> getSupplierIdByName(String name) async {
    final db = await DBService.database;
    await createTable(db);

    return _duplicateOn(db, name);
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

    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              tableName,
              {'account_id': ensured},
              where: 'id = ?',
              whereArgs: [supplierId],
            ));

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
