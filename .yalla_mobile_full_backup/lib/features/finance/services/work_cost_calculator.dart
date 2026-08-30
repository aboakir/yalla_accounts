import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/finance/services/monthly_expense_service.dart';

class WorkCostCalculator {
  /// تحسب تكلفة العمل الفعلية بناءً على الفرق بين الإيرادات ومصاريف الورشة
  static Future<double> calculateForMonth(DateTime date) async {
    final String monthStr = DateFormat('yyyy-MM').format(date);

    // ✅ جلب مجموع الإيرادات من الإصلاحات
    final List repairs = await RepairDatabaseService.getAllRepairs();
    final repairsForMonth = repairs
        .where((r) => DateFormat('yyyy-MM').format(r.receivedDate) == monthStr);

    double totalIncome = 0;
    for (var r in repairsForMonth) {
      totalIncome += r.incomeAmount ?? 0;
    }

    // ✅ جلب المصاريف من جدول المصاريف الشهرية
    final monthly = await MonthlyExpenseService.getByMonth(monthStr);
    final totalExpenses = monthly?.total ?? 0.0;

    final workCost = totalIncome - totalExpenses;
    return workCost >= 0 ? workCost : 0;
  }
}
