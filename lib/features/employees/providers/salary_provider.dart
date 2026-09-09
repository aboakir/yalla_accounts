import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_entitlement_service.dart';

final salaryProvider =
    StateNotifierProvider<SalaryNotifier, double>((ref) => SalaryNotifier());

/// All previews read the same persisted employee/attendance and entitlement
/// calculation used by accrual. Legacy arguments remain source-compatible.
class SalaryNotifier extends StateNotifier<double> {
  SalaryNotifier() : super(0);
  final Map<String, double> _byEmployee = {};
  Future<double> calculateAndReturn({
    required String employeeId,
    required double baseSalary,
    required int totalWorkDaysInMonth,
    required List<dynamic> attendanceRecords,
    required DateTime periodStart,
    required DateTime periodEnd,
    bool payOfficialHolidays = false,
  }) async {
    final employee = await EmployeeDatabaseService.getById(employeeId);
    if (employee == null) throw StateError('الموظف غير موجود.');
    final result = await PayrollEntitlementService.calculate(
        employee: employee, periodStart: periodStart, periodEnd: periodEnd);
    _byEmployee[employeeId] = result.netBeforeAdvances;
    if (mounted) state = result.netBeforeAdvances;
    return result.netBeforeAdvances;
  }

  Future<void> calculateSalaryFromAttendance({
    required String employeeId,
    required double baseSalary,
    required int totalWorkDaysInMonth,
    required List<dynamic> attendanceRecords,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    await calculateAndReturn(
        employeeId: employeeId,
        baseSalary: baseSalary,
        totalWorkDaysInMonth: totalWorkDaysInMonth,
        attendanceRecords: attendanceRecords,
        periodStart: periodStart,
        periodEnd: periodEnd);
  }

  double getSalary(String employeeId) => _byEmployee[employeeId] ?? 0;
}
