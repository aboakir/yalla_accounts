// 📁 lib/features/finance/services/finance_report_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class FinanceReportService {
  static Future<Database> _db() => DBService.database;

  /// 🔹 إيرادات الإصلاحات شهريًا من GL account 4000.
  static Future<Map<String, double>> getMonthlyIncomeFromRepairs() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT strftime('%Y-%m', e.date) AS month,
             COALESCE(SUM(l.credit-l.debit),0) AS income
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code='4000'
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

  static Future<Map<String, double>> _monthlyExpense(String condition) async {
    final db = await _db();
    final rows = await db.rawQuery("""
      SELECT substr(e.date,1,7) month, SUM(l.debit-l.credit) total
      FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id JOIN accounts a ON a.id=l.account_id
      WHERE $condition GROUP BY substr(e.date,1,7) ORDER BY month
    """);
    return {
      for (final r in rows)
        r['month'].toString(): (r['total'] as num).toDouble()
    };
  }

  static Future<Map<String, double>> getMonthlySalaries() =>
      _monthlyExpense("a.code='5100' OR a.code LIKE '5100.%'");
  static Future<Map<String, double>> getMonthlyPurchases() =>
      _monthlyExpense("a.code='5005' OR a.code LIKE '5005.%'");
  static Future<
      Map<String,
          double>> getMonthlyOtherExpenses() => _monthlyExpense(
      "(UPPER(a.type)='EXPENSE' OR a.code LIKE '5%') AND a.code<>'5100' AND a.code NOT LIKE '5100.%' AND a.code<>'5005' AND a.code NOT LIKE '5005.%'");
}
