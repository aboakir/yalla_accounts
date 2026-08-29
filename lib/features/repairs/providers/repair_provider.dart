import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

/// مزود لإدارة قائمة الإصلاحات
final repairListProvider =
    StateNotifierProvider<RepairListNotifier, List<Repair>>((ref) {
  return RepairListNotifier();
});

/// ✅ مزود مباشر لقائمة الإصلاحات (للاستخدام في الواجهات)
final repairsProvider = Provider<List<Repair>>((ref) {
  return ref.watch(repairListProvider);
});

class RepairListNotifier extends StateNotifier<List<Repair>> {
  RepairListNotifier() : super([]) {
    loadRepairs();
  }

  Future<void> loadRepairs() async {
    final repairs = await RepairDatabaseService.getAllRepairs();
    state = repairs.reversed.toList();
  }

  Future<void> addRepair(Repair repair) async {
    await RepairDatabaseService.insertRepair(repair);
    await loadRepairs();
  }

  Future<void> updateRepair(Repair repair) async {
    await RepairDatabaseService.updateRepair(repair);
    await loadRepairs();
  }

  Future<void> deleteRepair(String id) async {
    await RepairDatabaseService.deleteRepair(id);
    await loadRepairs();
  }

  Future<void> approveLedgerEntry(String repairId) async {
    await loadRepairs();
  }

  void filterArchived(bool isArchived) {
    state = state.where((repair) => repair.isArchived == isArchived).toList();
  }
}
