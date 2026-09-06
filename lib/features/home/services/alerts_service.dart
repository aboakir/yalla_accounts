import 'package:yalla_accounts/features/finance/services/collection_service.dart';

class AlertEntity {
  final String id;
  final String message;
  final DateTime timestamp;
  final String type;

  AlertEntity({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.type,
  });
}

/// P12 smart collection alerts. Amount/date truth comes from GL +
/// collection_due_dates + canonical cheque lifecycle.
class AlertsService {
  Future<List<AlertEntity>> getSmartAlerts() async {
    final raw = await CollectionService.loadAlerts();
    return raw
        .map((item) => AlertEntity(
              id: item.id,
              message: item.message,
              timestamp: item.timestamp,
              type: item.severity,
            ))
        .toList();
  }
}
