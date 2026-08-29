// 📁 lib/features/home/widgets/operations_distribution_chart.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:yalla_accounts/features/home/providers/dashboard_provider.dart';

class OperationsDistributionChart extends ConsumerWidget {
  final bool distributionOnly;
  const OperationsDistributionChart({
    super.key,
    this.distributionOnly = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDist = ref.watch(operationsDistributionProvider);

    return asyncDist.when(
      data: (dist) {
        final sections = dist.entries.map((e) {
          final color = Colors.primaries[
              dist.keys.toList().indexOf(e.key) % Colors.primaries.length];
          return PieChartSectionData(
            value: e.value.toDouble(),
            title: '${e.key}\n${e.value}',
            radius: 50,
            titleStyle: const TextStyle(fontSize: 12, color: Colors.white),
            color: color,
          );
        }).toList();

        return PieChart(
          PieChartData(
            sections: sections,
            centerSpaceRadius: distributionOnly ? 40 : 0,
            sectionsSpace: 2,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ عرض الرسم: $e')),
    );
  }
}
