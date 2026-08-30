import 'package:yalla_accounts/features/clients/services/client_service.dart';
import '../models/client_report.dart';

class ClientReportService {
  static Future<ClientReport> getClientReport() async {
    final allClients = await ClientService.getAllClients();
    final totalClients = allClients.length;

    // افتراضياً: كل العملاء فعالين (يمكن تعديل حسب بيانات فعلية)
    final activeClients = totalClients;
    const inactiveClients = 0;

    return ClientReport(
      totalClients: totalClients,
      activeClients: activeClients,
      inactiveClients: inactiveClients,
    );
  }
}
