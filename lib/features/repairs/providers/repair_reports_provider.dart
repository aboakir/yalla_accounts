// 📁 lib/features/repairs/providers/repair_reports_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
// 📁 lib/features/repairs/providers/repair_report_provider.dart

import 'package:yalla_accounts/features/repairs/services/repair_ledger_query_service.dart';

/// 🔹 الإيرادات الشهرية
final monthlyRevenueProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await RepairLedgerQueryService.getMonthlyRevenue();
});

/// 🔹 الذمم غير المسددة شهريًا
final monthlyDebtProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await RepairLedgerQueryService.getMonthlyOutstandingDebts();
});

/// 🔹 عدد الإصلاحات شهريًا
final monthlyRepairCountProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await RepairLedgerQueryService.getRepairCountsByMonth();
});

/// 🔹 توزيع الإيرادات حسب نوع الجهة (تأمين / أفراد)
final revenueByPayerTypeProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await RepairLedgerQueryService.getRevenueByBeneficiaryType();
});

/// 🔹 الملفات الأعلى في الذمم
final topDebtorsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await RepairLedgerQueryService.getTopOutstandingRepairs(limit: 5);
});

/// 🔹 الإيرادات السنوية
final yearlyRevenueProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await RepairLedgerQueryService.getYearlyRevenue();
});

final repairReportsProvider = FutureProvider<List<Repair>>((ref) async {
  final repairs = await RepairDatabaseService.getAllRepairs();
  if (repairs.isEmpty) return repairs;

  final db = await DBService.database;
  final rows = await db.rawQuery('''
    WITH paid AS (${RepairFinancialTruthService.paidByRepairSql})
    SELECT repair_id, COALESCE(paid, 0) AS paid FROM paid
  ''');
  final paidByRepair = <String, double>{
    for (final row in rows)
      if (row['repair_id'] != null)
        row['repair_id'].toString(): (row['paid'] as num?)?.toDouble() ?? 0.0,
  };

  return repairs
      .map((repair) => repair.copyWith(
            paidAmount: paidByRepair[repair.id] ?? 0.0,
          ))
      .toList(growable: false);
});

/// 🔔 مزود عدد الملفات غير المسددة منذ أكثر من 30 يومًا
final overdueUnpaidCountProvider = FutureProvider<int>((ref) async {
  return await RepairLedgerQueryService.getOverdueUnpaidRepairsCount();
});
