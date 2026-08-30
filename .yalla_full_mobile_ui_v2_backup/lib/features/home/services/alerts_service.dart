// 📁 lib/features/home/services/alerts_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

/// نموذج أولي لتمثيل تنبيه ذكي قبل الإرسال للـ Provider
class AlertEntity {
  final String id;
  final String message;
  final DateTime timestamp;
  final String type; // 'info', 'warning', 'critical'

  AlertEntity({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.type,
  });
}

/// خدمة لجلب التنبيهات الذكية (Smart Notifications)
class AlertsService {
  /// يجلب الأقساط غير المدفوعة والمتأخرة أو القريبة من الاستحقاق
  /// ويحوّلها إلى تنبيهات ذكية
  Future<List<AlertEntity>> getSmartAlerts() async {
    final Database db = await RepairDatabaseService.database;
    final now = DateTime.now();

    // استعلام عن الأقساط غير المدفوعة
    final rows = await db.query(
      'accounts_receivable',
      where: 'isPaid = ?',
      whereArgs: [0],
    );

    final List<AlertEntity> alerts = [];

    for (final row in rows) {
      final dueDate = DateTime.parse(row['dueDate'] as String);
      final daysDiff = dueDate.difference(now).inDays;
      // إذا متأخرة أو أقل من يوم للاستحقاق
      if (dueDate.isBefore(now) || daysDiff <= 1) {
        final repairId = row['repairId'] as String;
        final message = dueDate.isBefore(now)
            ? 'قسط لطلب إصلاح $repairId متأخر منذ ${-daysDiff} يومًا'
            : 'قسط لطلب إصلاح $repairId يستحق بعد $daysDiff يومًا';
        final type = dueDate.isBefore(now) ? 'critical' : 'warning';
        alerts.add(AlertEntity(
          id: '${repairId}_${row['id']}',
          message: message,
          timestamp: dueDate,
          type: type,
        ));
      }
    }

    return alerts;
  }
}
