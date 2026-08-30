import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/inventory/models/inventory_item.dart';

class InventoryService {
  static const String tableName = 'inventory_items';

  // نستخدم DBService كمصدر وحيد للقاعدة
  static Future<Database> get _db async => DBService.database;

  /// إنشاء الجدول (ID رقمي أوتوإنكريمنت ليتماشى مع الموديل الحالي)
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        description TEXT
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_name ON $tableName(name);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_category ON $tableName(category);',
    );
  }

  /// إضافة عنصر جديد
  /// ملاحظة: بما أن id أوتوإنكريمنت، ما بنرسل id في insert.
  static Future<int> insertItem(InventoryItem item) async {
    final db = await _db;
    final map = Map<String, Object?>.from(item.toMap())..remove('id');
    return await db.insert(
      tableName,
      map,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// تحديث عنصر قائم (يتطلب id غير null)
  static Future<int> updateItem(InventoryItem item) async {
    if (item.id == null) {
      throw ArgumentError('InventoryService.updateItem: id is required.');
    }
    final db = await _db;
    return await db.update(
      tableName,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// حذف عنصر
  static Future<int> deleteItem(int id) async {
    final db = await _db;
    return await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// جلب كل العناصر
  static Future<List<InventoryItem>> getAllItems() async {
    final db = await _db;
    final rows = await db.query(tableName, orderBy: 'name ASC');
    return rows.map((m) => InventoryItem.fromMap(m)).toList();
  }

  /// جلب عنصر واحد بالمعرف (اختياري)
  static Future<InventoryItem?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InventoryItem.fromMap(rows.first);
  }
}
