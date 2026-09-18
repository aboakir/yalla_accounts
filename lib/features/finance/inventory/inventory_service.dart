// 📁 lib/features/finance_restructured/inventory/inventory_service.dart

import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'inventory_item_model.dart';

class InventoryService {
  static Database? _db;

  static Future<Database> _getDatabase() async {
    if (_db != null && _db!.isOpen) return _db!;
    final db = await DBService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_items(
        id TEXT PRIMARY KEY,
        name TEXT,
        partNumber TEXT,
        purchasePrice REAL,
        sellingPrice REAL,
        quantityInStock INTEGER,
        unit TEXT,
        category TEXT,
        lastUpdated TEXT
      )
    ''');
    _db = db;
    return db;
  }

  static Future<void> addItem(InventoryItem item) async {
    final db = await _getDatabase();
    await db.insert('inventory_items', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateItem(InventoryItem item) async {
    final db = await _getDatabase();
    await db.update('inventory_items', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  static Future<void> deleteItem(String id) async {
    final db = await _getDatabase();
    await db.delete('inventory_items', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<InventoryItem>> getAllItems() async {
    final db = await _getDatabase();
    final maps = await db.query('inventory_items');
    return maps.map((map) => InventoryItem.fromMap(map)).toList();
  }

  static Future<void> adjustStock(String id, int change) async {
    final db = await _getDatabase();
    final maps =
        await db.query('inventory_items', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return;
    final item = InventoryItem.fromMap(maps.first);
    final newQty = item.quantityInStock + change;
    await updateItem(item.copyWith(
      quantityInStock: newQty,
      lastUpdated: DateTime.now(),
    ));
  }
}

extension on InventoryItem {
  InventoryItem copyWith({
    String? id,
    String? name,
    String? partNumber,
    double? purchasePrice,
    double? sellingPrice,
    int? quantityInStock,
    String? unit,
    String? category,
    DateTime? lastUpdated,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      partNumber: partNumber ?? this.partNumber,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      quantityInStock: quantityInStock ?? this.quantityInStock,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
