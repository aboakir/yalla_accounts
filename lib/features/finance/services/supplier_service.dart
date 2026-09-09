import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:sqflite/sqflite.dart';
import '../../suppliers/services/supplier_service.dart' as canonical;
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/models/supplier_model.dart';

class SupplierService {
  /// الجدول صار يتنشأ من DBService. خلّيها موجودة لو بدك تناديها باختبارات فقط.
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT
      )
    ''');
  }

  static Future<void> addSupplier(SupplierModel supplier) async {
    final db = await DBService.database;
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              'suppliers',
              supplier.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            ));
  }

  static Future<List<SupplierModel>> getAllSuppliers() async {
    final db = await DBService.database;
    final maps = await db.query('suppliers', orderBy: 'LOWER(name)');
    return maps.map((m) => SupplierModel.fromMap(m)).toList();
  }

  static Future<void> deleteSupplier(String id) async {
    await canonical.SupplierService.deleteSupplier(id);
  }
}
