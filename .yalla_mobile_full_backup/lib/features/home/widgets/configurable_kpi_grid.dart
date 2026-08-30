// 📁 lib/features/home/widgets/configurable_kpi_grid.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:reorderables/reorderables.dart'; // استخدم الحزمة أو ابحث عن بديل داخلي لإعادة الترتيب
import 'package:yalla_accounts/core/providers/kpi_items_provider.dart';
import 'package:yalla_accounts/shared/widgets/kpi_card.dart';

/// شبكة بطاقات KPI قابلة للسحب والإفلات لإعادة الترتيب والتخصيص
class ConfigurableKpiGrid extends ConsumerWidget {
  const ConfigurableKpiGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(kpiItemsProvider);

    return ReorderableWrap(
      spacing: 16,
      runSpacing: 16,
      padding: const EdgeInsets.all(8),
      onReorder: (oldIndex, newIndex) {
        ref.read(kpiItemsProvider.notifier).reorder(oldIndex, newIndex);
      },
      children: List.generate(items.length, (index) {
        final item = items[index];
        return SizedBox(
          key: ValueKey(item.title),
          width: 170,
          child: KpiCard(
            title: item.title,
            value: item.value,
            highlight: item.highlight,
          ),
        );
      }),
    );
  }
}
