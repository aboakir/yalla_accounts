// 📁 lib/core/providers/smart_alerts_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/home/services/alerts_service.dart';

/// نموذج تنبيه ذكي
class SmartAlert {
  final String id;
  final String message;
  final DateTime timestamp;
  final AlertType type;

  SmartAlert({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.type,
  });
}

/// أنواع التنبيهات
enum AlertType { info, warning, critical }

/// Provider لجلب قائمة التنبيهات الذكية من الخدمة
final smartAlertsProvider = FutureProvider<List<SmartAlert>>((ref) async {
  final service = AlertsService();
  final rawAlerts = await service.getSmartAlerts();
  return rawAlerts
      .map((a) => SmartAlert(
            id: a.id,
            message: a.message,
            timestamp: a.timestamp,
            type: AlertType.values.firstWhere(
              (e) => e.name == a.type,
              orElse: () => AlertType.info,
            ),
          ))
      .toList();
});
