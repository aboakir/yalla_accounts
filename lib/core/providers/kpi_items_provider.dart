// 📁 lib/core/providers/kpi_items_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/home/models/kpi_item.dart';

/// نموذج KPIItem (تأكد من أنّه موجود ويحتوي الحقول التالية)
/// class KPIItem { final String title; final num value; final bool highlight; ... }

/// StateNotifier لإدارة قائمة الـ KPI
class KpiItemsNotifier extends StateNotifier<List<KPIItem>> {
  KpiItemsNotifier() : super([]);

  /// تحميل بيانات وهميّة (Mock)
  void loadMock() {
    state = [
      KPIItem(title: 'أوامر اليوم', value: 8, highlight: false),
      KPIItem(title: 'إيراد الشهر', value: 3200.0, highlight: true),
      KPIItem(title: 'الموظفون النشطون', value: 5, highlight: false),
      KPIItem(title: 'المشتريات المعلقة', value: 3, highlight: false),
    ];
  }

  /// إعادة ترتيب بعد السحب والإفلات
  void reorder(int oldIndex, int newIndex) {
    final items = [...state];
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    state = items;
  }
}

/// المزود العام لقائمة KPI
final kpiItemsProvider = StateNotifierProvider<KpiItemsNotifier, List<KPIItem>>(
  (ref) => KpiItemsNotifier(),
);
