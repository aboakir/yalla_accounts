import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
// 📁 lib/core/services/db/tables/report_tables.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

// احذف: import 'package:flutter/foundation.dart';

class ReportTables {
  // 📊 إنشاء جداول التقارير والمصروفات
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createMonthlyExpensesTable(db);
  }

  // 💸 جدول المصروفات الشهرية
  static Future<void> _createMonthlyExpensesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS monthly_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        month TEXT NOT NULL UNIQUE,
        salaries REAL NOT NULL,
        raw_materials REAL NOT NULL,
        electricity REAL NOT NULL,
        rent REAL NOT NULL,
        other REAL NOT NULL,
        date TEXT
      )
    ''');

    await _ensureMonthlyExpensesIndexes(db);
  }

  static Future<void> _ensureMonthlyExpensesIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_monthly_expenses_date ON monthly_expenses(date);');
  }

  static Future<void> _ensureMonthlyExpensesDate(DatabaseExecutor db) async {
    await _ensureColumn(db, 'monthly_expenses', 'date', 'TEXT');
  }

  static Future<void> _ensureColumn(
      DatabaseExecutor db, String table, String column, String type) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((c) => (c['name'] as String?) == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
    }
  }

  // 🔄 ترقية الجداول
  static Future<void> onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 26) {
      await _createMonthlyExpensesTable(db);
      await _ensureMonthlyExpensesDate(db);
    }
  }

  // 🎯 واجهات الاستخدام
  static Future<Map<String, dynamic>> getMonthlyExpenses(
      DatabaseExecutor db, int year, int month) async {
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';
    final result = await db.query(
      'monthly_expenses',
      where: 'month = ?',
      whereArgs: [monthStr],
      limit: 1,
    );

    return result.isNotEmpty
        ? Map<String, dynamic>.from(result.first)
        : {
            'month': monthStr,
            'salaries': 0.0,
            'raw_materials': 0.0,
            'electricity': 0.0,
            'rent': 0.0,
            'other': 0.0,
          };
  }

  static Future<int> updateMonthlyExpenses(
          DatabaseExecutor db, Map<String, dynamic> data) =>
      SyncFoundationService.writeOn(
          db, (txn) => _updateMonthlyExpensesOn(txn, data));

  static Future<int> _updateMonthlyExpensesOn(
      DatabaseExecutor db, Map<String, dynamic> data) async {
    final existing = await db.query(
      'monthly_expenses',
      where: 'month = ?',
      whereArgs: [data['month']],
    );

    if (existing.isEmpty) {
      return await db.insert('monthly_expenses', {
        ...data,
        'date': DateTime.now().toIso8601String(),
      });
    } else {
      return await db.update(
        'monthly_expenses',
        {
          ...data,
          'date': DateTime.now().toIso8601String(),
        },
        where: 'month = ?',
        whereArgs: [data['month']],
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getExpensesByYear(
      DatabaseExecutor db, int year) async {
    return await db.query(
      'monthly_expenses',
      where: 'month LIKE ?',
      whereArgs: ['$year-%'],
      orderBy: 'month DESC',
    );
  }

  static Future<Map<String, double>> getYearlyExpensesSummary(
      DatabaseExecutor db, int year) async {
    final expenses = await getExpensesByYear(db, year);

    double salaries = 0.0;
    double materials = 0.0;
    double electricity = 0.0;
    double rent = 0.0;
    double other = 0.0;

    for (final expense in expenses) {
      salaries += (expense['salaries'] as num?)?.toDouble() ?? 0.0;
      materials += (expense['raw_materials'] as num?)?.toDouble() ?? 0.0;
      electricity += (expense['electricity'] as num?)?.toDouble() ?? 0.0;
      rent += (expense['rent'] as num?)?.toDouble() ?? 0.0;
      other += (expense['other'] as num?)?.toDouble() ?? 0.0;
    }

    return {
      'salaries': salaries,
      'raw_materials': materials,
      'electricity': electricity,
      'rent': rent,
      'other': other,
      'total': salaries + materials + electricity + rent + other,
    };
  }

  // 📈 تقارير الأداء
  static Future<Map<String, dynamic>> getPerformanceReport(
      DatabaseExecutor db, DateTime startDate, DateTime endDate) async {
    // إجمالي الإيرادات من الفواتير
    final revenueResult = await db.rawQuery('''
      SELECT SUM(total) as total_revenue FROM invoices 
      WHERE date BETWEEN ? AND ?
    ''', [
      startDate.toIso8601String().split('T').first,
      endDate.toIso8601String().split('T').first,
    ]);

    final totalRevenue =
        (revenueResult.first['total_revenue'] as num?)?.toDouble() ?? 0.0;

    // إجمالي المصروفات - الإصدار المصحح
    final expensesResult = await db.rawQuery('''
      SELECT 
        SUM(salaries) as salaries,
        SUM(raw_materials) as materials,
        SUM(electricity) as electricity,
        SUM(rent) as rent,
        SUM(other) as other
      FROM monthly_expenses 
      WHERE month BETWEEN ? AND ?
    ''', [
      '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}',
      '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}',
    ]);

    final expRow = expensesResult.first;

    // الإصدار المصحح لحساب totalExpenses
    final totalExpenses = ((expRow['salaries'] as num?)?.toDouble() ?? 0.0) +
        ((expRow['materials'] as num?)?.toDouble() ?? 0.0) +
        ((expRow['electricity'] as num?)?.toDouble() ?? 0.0) +
        ((expRow['rent'] as num?)?.toDouble() ?? 0.0) +
        ((expRow['other'] as num?)?.toDouble() ?? 0.0);

    // عدد الإصلاحات المكتملة
    final repairsResult = await db.rawQuery('''
      SELECT COUNT(*) as completed_repairs FROM repairs
      WHERE receivedDate BETWEEN ? AND ?
        AND status = 'CLOSED'
        AND COALESCE(isArchived, 0) = 1
    ''', [
      startDate.toIso8601String().split('T').first,
      endDate.toIso8601String().split('T').first,
    ]);

    final completedRepairs =
        (repairsResult.first['completed_repairs'] as num?)?.toInt() ?? 0;

    return {
      'period':
          '${startDate.toIso8601String().split('T').first} إلى ${endDate.toIso8601String().split('T').first}',
      'total_revenue': totalRevenue,
      'total_expenses': totalExpenses,
      'net_profit': totalRevenue - totalExpenses,
      'completed_repairs': completedRepairs,
      'profit_margin': totalRevenue > 0
          ? ((totalRevenue - totalExpenses) / totalRevenue * 100)
          : 0.0,
    };
  }
  // قبل السطر الأخير } أضف:

  // 🎯 الدوال المفقودة
  static Future<void> setRepairThumbnailPath({
    required DatabaseExecutor db,
    required String repairId,
    String? path,
  }) async {
    await db.update(
      'repairs',
      {
        'thumbnail_path': path,
        'thumbnail_updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [repairId],
    );
  }

  static Future<String> createInvoiceForRepair({
    required DatabaseExecutor db,
    required String repairId,
    required int? clientId,
    required double total,
  }) async {
    final invoiceId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'invoices',
      {
        'id': invoiceId,
        'repair_id': repairId,
        'client_id': clientId,
        'subtotal': total,
        'vat_amount': 0.0,
        'total': total,
        'status': 'unpaid',
        'notes': null,
        'method': null,
        'note': null,
        'post_to_gl': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return invoiceId;
  }
}
