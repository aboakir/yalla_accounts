// 📁 lib/features/employees/providers/salary_list_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/employees/models/salary.dart';
import 'package:yalla_accounts/features/employees/services/salary_database_service.dart';

/// مزود لحالة قائمة الرواتب
final salaryListProvider =
    StateNotifierProvider<SalaryListNotifier, List<Salary>>(
  (ref) => SalaryListNotifier(),
);

class SalaryListNotifier extends StateNotifier<List<Salary>> {
  SalaryListNotifier() : super([]) {
    loadSalaries();
  }

  /// تحميل جميع قسائم الرواتب من قاعدة البيانات
  Future<void> loadSalaries() async {
    final data = await SalaryDatabaseService.getSalaries();
    state = data;
  }

  /// إضافة قسيمة راتب جديدة أو تعديلها
  Future<void> addOrUpdateSalary(Salary salary) async {
    await SalaryDatabaseService.insertSalary(salary);
    await loadSalaries();
  }

  /// حذف قسيمة راتب معينة
  Future<void> deleteSalary(String employeeId, String month) async {
    await SalaryDatabaseService.deleteSalary(
      employeeId: employeeId,
      month: month,
    );
    await loadSalaries();
  }

  /// جلب قسيمة راتب حسب الموظف والشهر
  Salary? getSalary(String employeeId, String month) {
    try {
      return state.firstWhere(
        (s) => s.employeeId == employeeId && s.month == month,
      );
    } catch (_) {
      return null;
    }
  }

  /// تصفية الرواتب حسب الشهر
  List<Salary> filterByMonth(String month) {
    return state.where((s) => s.month == month).toList();
  }

  /// تصفية الرواتب حسب موظف
  List<Salary> filterByEmployee(String employeeId) {
    return state.where((s) => s.employeeId == employeeId).toList();
  }
}
