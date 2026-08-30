import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class LedgerDatabaseService {
  /// إنشاء جدول القيود المحاسبية عند إنشاء القاعدة لأول مرة
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ledger_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        description TEXT,
        debit_account TEXT NOT NULL,
        credit_account TEXT NOT NULL,
        amount REAL NOT NULL,
        reference_type TEXT,
        reference_id TEXT
      )
    ''');
  }

  /// التأكد من وجود الجدول (عند تشغيل التطبيق)
  static Future<void> ensureTableExists() async {
    final db = await DBService.database;
    await createTable(db);
  }

  /// P1.005 — legacy ledger is read-only.
  static Future<void> deleteEntriesByReference({
    required String referenceType,
    required String referenceId,
  }) async {
    throw StateError(
      'Legacy ledger_entries mutation is disabled by P1.005. '
      'Use the owning business service and PostingEngine.',
    );
  }

  /// استرجاع القيود حسب نوع المرجع
  static Future<List<Map<String, dynamic>>> getEntriesByType(
      String type) async {
    final db = await DBService.database;
    return await db.query(
      'ledger_entries',
      where: 'reference_type = ?',
      whereArgs: [type],
      orderBy: 'date DESC',
    );
  }
}
