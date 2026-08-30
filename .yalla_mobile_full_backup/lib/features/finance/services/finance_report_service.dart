// 📁 lib/features/finance/services/finance_report_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class FinanceReportService {
  static Future<Database> _db() => DBService.database;

  /// 🔹 إيرادات الإصلاحات شهريًا (من repairs.fileValue)
  static Future<Map<String, double>> getMonthlyIncomeFromRepairs() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT strftime('%Y-%m', receivedDate) AS month,
             IFNULL(SUM(fileValue), 0)       AS income
      FROM repairs
      GROUP BY month
      ORDER BY month
    ''');

    final out = <String, double>{};
    for (final r in rows) {
      final m = (r['month'] ?? 'غير معروف').toString();
      final v = (r['income'] as num?)?.toDouble() ?? 0.0;
      out[m] = v;
    }
    return out;
  }

  /// 🔹 مجموع الرواتب شهريًا (من جدول salaries الحقيقي)
  /// ملاحظة: جدول salaries عندك يحتوي عمود month بصيغة 'YYYY-MM'
  /// وعمود total لقيمة الراتب لذلك الشهر.
  static Future<Map<String, double>> getMonthlySalaries() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT month AS month,
             IFNULL(SUM(total), 0) AS total
      FROM salaries
      GROUP BY month
      ORDER BY month
    ''');

    final out = <String, double>{};
    for (final r in rows) {
      final m = (r['month'] ?? 'غير معروف').toString();
      final v = (r['total'] as num?)?.toDouble() ?? 0.0;
      out[m] = v;
    }
    return out;
  }

  /// 🔹 مجموع المشتريات شهريًا (من purchases)
  /// Schema: quantity INTEGER, pricePerUnit REAL, date TEXT
  /// نجمع (quantity * pricePerUnit) لكل شهر.
  static Future<Map<String, double>> getMonthlyPurchases() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT strftime('%Y-%m', date)              AS month,
             IFNULL(SUM(quantity * pricePerUnit), 0) AS total
      FROM purchases
      GROUP BY month
      ORDER BY month
    ''');

    final out = <String, double>{};
    for (final r in rows) {
      final m = (r['month'] ?? 'غير معروف').toString();
      final v = (r['total'] as num?)?.toDouble() ?? 0.0;
      out[m] = v;
    }
    return out;
  }

  /// 🔹 مصروفات تشغيل أخرى شهريًا (من monthly_expenses)
  /// نأخذ (electricity + rent + other) لكل شهر — بدون رواتب كي لا نكررها.
  /// Schema: month TEXT UNIQUE, salaries, raw_materials, electricity, rent, other, date?
  static Future<Map<String, double>> getMonthlyOtherExpenses() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT month AS month,
             IFNULL(electricity, 0) + IFNULL(rent, 0) + IFNULL(other, 0) AS total
      FROM monthly_expenses
      ORDER BY month
    ''');

    final out = <String, double>{};
    for (final r in rows) {
      final m = (r['month'] ?? 'غير معروف').toString();
      final v = (r['total'] as num?)?.toDouble() ?? 0.0;
      out[m] = v;
    }
    return out;
  }
}
