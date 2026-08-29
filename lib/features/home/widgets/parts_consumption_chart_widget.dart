// 📁 lib/features/home/widgets/parts_consumption_chart_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:yalla_accounts/core/providers/parts_usage_provider.dart';

/// Widget لعرض استهلاك قطع الغيار على شكل مخطط شريطي
class PartsConsumptionChartWidget extends ConsumerWidget {
  const PartsConsumptionChartWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(partsUsageProvider);

    return statsAsync.when(
      data: (stats) {
        final consumptions = stats.consumptions;
        if (consumptions.isEmpty) {
          return const Center(child: Text('لا توجد بيانات لاستهلاك القطع'));
        }

        // نأخذ أعلى خمسة أجزاء استهلاكًا
        final topParts = consumptions.toList()
          ..sort((a, b) => b.usedQuantity.compareTo(a.usedQuantity));
        final displayList = topParts.take(5).toList();

        return SizedBox(
          height: 250,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: displayList.first.usedQuantity.toDouble() * 1.2,
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= displayList.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        axisSide: meta.axisSide, // ✅ هذا السطر هو المطلوب
                        child: Text(
                          displayList[idx].partName,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: displayList.asMap().entries.map((e) {
                final idx = e.key;
                final part = e.value;
                return BarChartGroupData(
                  x: idx,
                  barRods: [
                    BarChartRodData(
                      toY: part.usedQuantity.toDouble(),
                      width: 16,
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.green,
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) =>
          const Center(child: Text('خطأ في تحميل بيانات استهلاك القطع')),
    );
  }
}
