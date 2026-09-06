import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import '../models/repair_report.dart';

class RepairReportService {
  static Future<RepairReport> getRepairReport() async {
    final allRepairs = await RepairDatabaseService.getAllRepairs();
    final totalRepairs = allRepairs.length;

    // P13: completion means formal CLOSED, never generic archive/cancel.
    final completedRepairs = allRepairs.where((r) => r.isClosed).length;
    final pendingRepairs = totalRepairs - completedRepairs;

    return RepairReport(
      totalRepairs: totalRepairs,
      completedRepairs: completedRepairs,
      pendingRepairs: pendingRepairs,
    );
  }
}
