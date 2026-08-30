// 📁 lib/features/repairs/services/purchase_part_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:yalla_accounts/features/repairs/models/purchase_part.dart';

class PurchasePartService {
  static Database? _database;

  static Future<Database> _getDatabase() async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'yalla_accounts.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_parts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            repairId TEXT,
            partName TEXT,
            cost REAL,
            purchaseDate TEXT
          )
        ''');
      },
    );
    return _database!;
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
