// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/providers/supplier_provider.dart
// مزود الموردين الرسمي — Yallah Accounts
// -----------------------------------------------------------------------------
// - تحميل الموردين من SupplierService
// - إضافة / تعديل / حذف
// - مزود للبحث (filteredSuppliersProvider)
// - مزود واحد فقط لإدارة القسم بالكامل
// -----------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/supplier.dart';
import '../services/supplier_service.dart';

// ============================================================================
// مزود: قائمة الموردين الكاملة
// ============================================================================
final suppliersProvider = FutureProvider<List<Supplier>>((ref) async {
  return SupplierService.getAllSuppliers();
});

// ============================================================================
// StateNotifier لإدارة التغييرات (Add / Update / Delete)
// ============================================================================
final suppliersNotifierProvider =
    StateNotifierProvider<SupplierNotifier, AsyncValue<List<Supplier>>>(
  (ref) => SupplierNotifier(ref),
);

class SupplierNotifier extends StateNotifier<AsyncValue<List<Supplier>>> {
  final Ref ref;

  SupplierNotifier(this.ref) : super(const AsyncLoading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await SupplierService.getAllSuppliers();
      if (!mounted) return;
      state = AsyncValue.data(list);
      ref.invalidate(suppliersProvider);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  // إضافة
  Future<void> addSupplier(Supplier supplier) async {
    await SupplierService.insertSupplier(supplier);
    await _load();
  }

  // تعديل
  Future<void> updateSupplier(Supplier supplier) async {
    await SupplierService.updateSupplier(supplier);
    await _load();
  }

  // حذف
  Future<void> deleteSupplier(String pid) async {
    await SupplierService.deleteSupplier(pid);
    await _load();
  }
}

// ============================================================================
// مزود للبحث عن الموردين
// ============================================================================
final filteredSuppliersProvider =
    Provider.family<List<Supplier>, String>((ref, query) {
  final asyncSuppliers = ref.watch(suppliersNotifierProvider);

  return asyncSuppliers.when(
    data: (list) {
      if (query.trim().isEmpty) return list;
      final q = query.trim().toLowerCase();
      return list.where((s) {
        return s.name.toLowerCase().contains(q) ||
            s.phone.toLowerCase().contains(q) ||
            s.address.toLowerCase().contains(q);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});
