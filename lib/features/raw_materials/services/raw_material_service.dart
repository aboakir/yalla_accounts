import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/raw_materials/models/raw_material.dart';

class RawMaterialService {
  static const String tableName = 'raw_materials';

  // نستخدم DBService كمصدر الحقيقة للـ DB
  static Future<Database> get _db async => DBService.database;

  /// إنشاء جدول المواد الخام (id رقمي أوتوإنكريمنت ليتماشى مع الموديل الحالي)
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        supplier TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        description TEXT
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_raw_materials_name ON $tableName(name);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_raw_materials_supplier ON $tableName(supplier);',
    );
  }

  /// إدخال مادة خام جديدة
  static Future<int> insertRawMaterial(RawMaterial material) async {
    final db = await _db;
    final map = Map<String, Object?>.from(material.toMap())
      ..remove('id'); // id أوتو
    return await db.insert(
      tableName,
      map,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// جلب جميع المواد الخام مرتبة بالاسم
  static Future<List<RawMaterial>> getAllRawMaterials() async {
    final db = await _db;
    final rows = await db.query(tableName, orderBy: 'name ASC');
    return rows.map((e) => RawMaterial.fromMap(e)).toList();
  }

  /// تحديث مادة خام موجودة (يتطلب id)
  static Future<int> updateRawMaterial(RawMaterial material) async {
    if (material.id == null) {
      throw ArgumentError(
          'RawMaterialService.updateRawMaterial: id is required.');
    }
    final db = await _db;
    return await db.update(
      tableName,
      material.toMap(),
      where: 'id = ?',
      whereArgs: [material.id],
    );
  }

  /// حذف مادة خام حسب المعرف
  static Future<int> deleteRawMaterial(int id) async {
    final db = await _db;
    return await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// (اختياري) جلب مادة واحدة بالمعرّف
  static Future<RawMaterial?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RawMaterial.fromMap(rows.first);
  }
}
