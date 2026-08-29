// 📁 lib/core/providers/critical_ops_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

/// نموذج لتمثيل دفعة قادمة أو متأخرة لأمر إصلاح
class CriticalOperation {
  final String repairId;
  final String vehicleNumber;
  final String paymentStatus;
  final DateTime dueDate;

  CriticalOperation({
    required this.repairId,
    required this.vehicleNumber,
    required this.paymentStatus,
    required this.dueDate,
  });
}

/// مزود لجلب قائمة العمليات الحرجة (الأقساط غير المدفوعة والمتأخرة أو القريبة جداً)
final criticalOpsProvider =
    FutureProvider.autoDispose<List<CriticalOperation>>((ref) async {
  // افتح قاعدة البيانات
  final db = await RepairDatabaseService.database;

  // استعلام عن جميع الأقساط غير المدفوعة
  final rows = await db.query(
    'accounts_receivable',
    where: 'isPaid = ?',
    whereArgs: [0],
  );

  final now = DateTime.now();
  final List<CriticalOperation> criticalList = [];

  for (final row in rows) {
    // قراءة تاريخ الاستحقاق وتحويله إلى DateTime
    final dueDate = DateTime.parse(row['dueDate'] as String);

    // إذا موعد الدفع قد مضى أو تبقى عليه يوم واحد أو أقل
    final daysDiff = dueDate.difference(now).inDays;
    if (dueDate.isBefore(now) || daysDiff <= 1) {
      final repairId = row['repairId'] as String;

      // جلب بيانات الإصلاح للحصول على رقم المركبة وحالة الدفع
      final repair = await RepairDatabaseService.getRepairById(repairId);
      if (repair != null) {
        criticalList.add(CriticalOperation(
          repairId: repairId,
          vehicleNumber: repair.vehicleNumber,
          paymentStatus: repair.paymentStatus ?? 'غير معروف',
          dueDate: dueDate,
        ));
      }
    }
  }

  return criticalList;
});
