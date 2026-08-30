import 'package:yalla_accounts/features/employees/services/employee_service.dart';
import '../models/employee_report.dart';

class EmployeeReportService {
  /// جلب تقرير الموظفين مع إحصائيات الحضور لليوم الحالي
  static Future<EmployeeReport> getEmployeeReport() async {
    final allEmployees = await EmployeeService.getAllEmployees(); // ✅ صح
    final totalEmployees = allEmployees.length;

    // TODO: اربط بحضور الموظفين لاحقًا
    final presentToday = totalEmployees;
    const absentToday = 0;

    return EmployeeReport(
      totalEmployees: totalEmployees,
      presentToday: presentToday,
      absentToday: absentToday,
    );
  }
}
