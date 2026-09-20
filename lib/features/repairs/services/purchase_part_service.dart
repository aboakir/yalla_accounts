// 📁 lib/features/repairs/services/purchase_part_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/features/repairs/models/purchase_part.dart';

class PurchasePartService {
  static Database? _database;

  static Future<Database> _getDatabase() async {
    if (_database != null && _database!.isOpen) return _database!;
    final db = await DBService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_parts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repairId TEXT,
        partName TEXT,
        cost REAL,
        purchaseDate TEXT
      )
    ''');
    _database = db;
    return db;
  }

  static Future<void> addPurchase(PurchasePart part) async {
    final db = await _getDatabase();
    await db.insert('purchase_parts', part.toMap());
  }

  static Future<List<PurchasePart>> getPurchasesByRepair(
      String repairId) async {
    final db = await _getDatabase();
    final maps = await db.query(
      'purchase_parts',
      where: 'repairId = ?',
      whereArgs: [repairId],
      orderBy: 'purchaseDate DESC',
    );
    return maps.map((e) => PurchasePart.fromMap(e)).toList();
  }

  static Future<void> deletePurchase(int id) async {
    final db = await _getDatabase();
    await db.delete('purchase_parts', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearAll() async {
    final db = await _getDatabase();
    await db.delete('purchase_parts');
  }
}
