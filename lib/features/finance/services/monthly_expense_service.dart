// 📁 lib/features/finance/services/monthly_expense_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/models/monthly_expense.dart';

class MonthlyExpenseService {
  static const tableName = 'monthly_expenses';

  /// إنشاء الجدول
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        month TEXT NOT NULL UNIQUE,
        salaries REAL NOT NULL,
        raw_materials REAL NOT NULL,
        electricity REAL NOT NULL,
        rent REAL NOT NULL,
        other REAL NOT NULL
      )
    ''');
  }

  /// إدخال سجل جديد أو تحديثه إذا كان موجودًا
  static Future<void> upsertExpense(MonthlyExpense expense) async {
    final db = await DBService.database;
    await db.insert(
      tableName,
      expense.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// حذف سجل حسب الشهر
  static Future<int> deleteByMonth(String month) async {
    final db = await DBService.database;
    return await db.delete(
      tableName,
      where: 'month = ?',
      whereArgs: [month],
    );
  }

  /// جلب سجل حسب الشهر
  static Future<MonthlyExpense?> getByMonth(String month) async {
    final db = await DBService.database;
    final result = await db.query(
      tableName,
      where: 'month = ?',
      whereArgs: [month],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return MonthlyExpense.fromMap(result.first);
  }

  /// جلب كل السجلات
  static Future<List<MonthlyExpense>> getAll() async {
    final db = await DBService.database;
    final result = await db.query(tableName, orderBy: 'month DESC');
    return result.map((e) => MonthlyExpense.fromMap(e)).toList();
  }

  /// جلب مجموع المصاريف لشهر معين
  static Future<double> getTotalForMonth(String month) async {
    final expense = await getByMonth(month);
    return expense?.total ?? 0.0;
  }
}
