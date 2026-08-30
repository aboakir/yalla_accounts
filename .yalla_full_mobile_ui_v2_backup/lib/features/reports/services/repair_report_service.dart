import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import '../models/repair_report.dart';

class RepairReportService {
  static Future<RepairReport> getRepairReport() async {
    final allRepairs = await RepairDatabaseService.getAllRepairs();
    final totalRepairs = allRepairs.length;

    // تأكد من تعديل هذا الشرط حسب الخاصية الصحيحة في Repair
    final completedRepairs =
        allRepairs.where((r) => r.vehicleStatus == 'مكتمل').length;
    final pendingRepairs = totalRepairs - completedRepairs;

    return RepairReport(
      totalRepairs: totalRepairs,
      completedRepairs: completedRepairs,
      pendingRepairs: pendingRepairs,
    );
  }
}
