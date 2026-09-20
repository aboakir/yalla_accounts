import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class MonthlyFinanceSummary {
  final String month;
  final double totalIncome; // من invoices.total
  final double totalSalaries; // من salaries.total
  final double totalExpenses; // من monthly_expenses (بدون بند salaries)
  final double netProfit; // income - salaries - expenses

  MonthlyFinanceSummary({
    required this.month,
    required this.totalIncome,
    required this.totalSalaries,
    required this.totalExpenses,
    required this.netProfit,
  });
}

class MonthlyFinanceService {
  /// تحليل الربح والخسارة لشهر محدد "YYYY-MM"
  static Future<MonthlyFinanceSummary> getSummaryForMonth(String month) async {
    final db = await DBService.database;

    // Revenue comes from the posted GL so repair settlements (+/-) are
    // reflected in the same month in which the financial adjustment occurred.
    final incomeRow = await db.rawQuery(
      '''
      SELECT IFNULL(SUM(l.credit-l.debit), 0) AS v
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code='4000'
        AND strftime('%Y-%m', e.date) = ?
      ''',
      [month],
    );
    final totalIncome = _asDouble(incomeRow.first['v']);

    // 2) الرواتب من جدول salaries (حقل total لكل موظف لنفس الشهر)
    final salariesRow = await db.rawQuery(
      '''
      SELECT IFNULL(SUM(total), 0) AS v
      FROM salaries
      WHERE month = ?
      ''',
      [month],
    );
    final totalSalaries = _asDouble(salariesRow.first['v']);

    // 3) المصاريف التشغيلية من monthly_expenses
    //    نستثني بند salaries هنا لتفادي الازدواجية مع جدول salaries.
    //    نستخدم month إن وُجد، وإلا نطابق على date (إن سُجّل بالتاريخ).
    final expensesRow = await db.rawQuery(
      '''
      SELECT IFNULL(SUM(
        IFNULL(raw_materials,0) + IFNULL(electricity,0) + IFNULL(rent,0) + IFNULL(other,0)
      ), 0) AS v
      FROM monthly_expenses
      WHERE month = ?
         OR (date IS NOT NULL AND strftime('%Y-%m', date) = ?)
      ''',
      [month, month],
    );
    final totalExpenses = _asDouble(expensesRow.first['v']);

    final netProfit = totalIncome - totalSalaries - totalExpenses;

    return MonthlyFinanceSummary(
      month: month,
      totalIncome: totalIncome,
      totalSalaries: totalSalaries,
      totalExpenses: totalExpenses,
      netProfit: netProfit,
    );
  }

  /// صيغة الشهر الحالي "YYYY-MM"
  static String getCurrentMonth() {
    final now = DateTime.now();
    return DateFormat('yyyy-MM').format(now);
  }

  // -------- helpers --------
  static double _asDouble(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
