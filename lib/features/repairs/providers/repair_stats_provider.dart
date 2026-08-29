import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/repairs/services/repair_stats_service.dart';

/// إجمالي عدد ملفات الإصلاح
final totalRepairsCountProvider = FutureProvider<int>((ref) async {
  return await RepairStatsService.getTotalRepairsCount();
});

/// عدد الملفات حسب حالة المركبة (مثل: قيد الإصلاح، جاهز للتسليم...)
final repairsCountByStatusProvider =
    FutureProvider.family<int, String>((ref, status) async {
  return await RepairStatsService.getRepairsCountByStatus(status);
});

/// مجموع قيمة الملفات (المدخلة في total_file_value)
final totalFileValueProvider = FutureProvider<double>((ref) async {
  return await RepairStatsService.getTotalFileValue();
});

/// مجموع المبالغ المدفوعة من كافة الملفات
final totalPaidAmountProvider = FutureProvider<double>((ref) async {
  return await RepairStatsService.getTotalPaidAmount();
});

/// ملخص شهري لعدد الملفات، إجمالي القيمة، وإجمالي المدفوع
final monthlyRepairSummaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await RepairStatsService.getMonthlyRepairSummary();
});

/// توزيع عدد الملفات حسب حالة السداد (لمخطط دائري)
final repairsCountByPaymentStatusProvider =
    FutureProvider<Map<String, int>>((ref) async {
  return await RepairStatsService.getRepairsCountByPaymentStatus();
});
