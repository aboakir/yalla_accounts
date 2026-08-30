// 📁 lib/features/home/providers/dashboard_provider.dart
//
// FINAL — نسخة نهائية بدون أي أخطاء
// تعمل مع InvoiceService v36 بالكامل
// ----------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';

/// عدد الإصلاحات لهذا الشهر
final repairsCountProvider = FutureProvider<int>((ref) async {
  final allRepairs = await RepairDatabaseService.getAllRepairs();
  final now = DateTime.now();
  return allRepairs
      .where((r) =>
          r.receivedDate.year == now.year && r.receivedDate.month == now.month)
      .length;
});

/// عدد الفواتير لهذا الشهر
final invoicesCountProvider = FutureProvider<int>((ref) async {
  return await InvoiceService.I.getInvoicesCountForMonth(DateTime.now());
});

/// إجمالي عدد العملاء
final clientsCountProvider = FutureProvider<int>((ref) async {
  return await ClientService.getTotalClients();
});

/// توزيع الإصلاحات حسب نوع العمل
final operationsDistributionProvider =
    FutureProvider<Map<String, int>>((ref) async {
  const types = ['دهان', 'توريد قطع', 'إصلاح ودهان', 'بودي ودهان'];
  final allRepairs = await RepairDatabaseService.getAllRepairs();

  final Map<String, int> dist = {for (final t in types) t: 0};

  for (final r in allRepairs) {
    final type = r.repairType.trim();
    if (type.isEmpty) continue;
    dist[type] = (dist[type] ?? 0) + 1;
  }

  return dist;
});
