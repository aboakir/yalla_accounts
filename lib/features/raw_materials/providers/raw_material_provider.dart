import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/raw_materials/models/raw_material.dart';
import 'package:yalla_accounts/features/raw_materials/services/raw_material_service.dart';

final rawMaterialListProvider =
    StateNotifierProvider<RawMaterialListNotifier, List<RawMaterial>>((ref) {
  return RawMaterialListNotifier();
});

class RawMaterialListNotifier extends StateNotifier<List<RawMaterial>> {
  RawMaterialListNotifier() : super([]) {
    loadMaterials();
  }

  /// تحميل جميع المواد الخام من الخدمة وتحديث الحالة
  Future<void> loadMaterials() async {
    try {
      final materials = await RawMaterialService.getAllRawMaterials();
      state = materials;
    } catch (e, st) {
      // هنا يمكن إضافة سجل الأخطاء أو إظهار رسالة للمستخدم
      debugPrint('خطأ أثناء تحميل المواد الخام: $e\n$st');
    }
  }

  /// إضافة مادة جديدة وتحديث الحالة محليًا
  Future<void> addMaterial(RawMaterial material) async {
    try {
      // يمكن تحسين: إضافة المادة الجديدة مباشرة إلى الحالة بدل إعادة التحميل الكامل
      await loadMaterials();
    } catch (e, st) {
      debugPrint('خطأ أثناء إضافة المادة: $e\n$st');
    }
  }

  /// تحديث مادة موجودة وتحديث الحالة محليًا
  Future<void> updateMaterial(RawMaterial material) async {
    try {
      await RawMaterialService.updateRawMaterial(material);
      // تحديث المادة في القائمة محليًا لتحسين الأداء
      state = [
        for (final item in state)
          if (item.id == material.id) material else item,
      ];
    } catch (e, st) {
      debugPrint('خطأ أثناء تحديث المادة: $e\n$st');
    }
  }

  /// حذف مادة حسب المعرف وتحديث الحالة محليًا
  Future<void> deleteMaterial(int id) async {
    try {
      await RawMaterialService.deleteRawMaterial(id);
      // إزالة المادة من الحالة محليًا دون إعادة تحميل كامل القائمة
      state = state.where((material) => material.id != id).toList();
    } catch (e, st) {
      debugPrint('خطأ أثناء حذف المادة: $e\n$st');
    }
  }
}
