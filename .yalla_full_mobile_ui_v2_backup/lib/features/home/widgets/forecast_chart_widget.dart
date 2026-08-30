// 📁 lib/features/home/widgets/forecast_chart_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/providers/forecast_stats_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

/// Widget لعرض توقعات الإيرادات على شكل مخطط خطي
class ForecastChartWidget extends ConsumerWidget {
  const ForecastChartWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(forecastStatsProvider);

    return statsAsync.when(
      data: (stats) {
        final spots = stats.history
            .asMap()
            .entries
            .map((e) => FlSpot(
                  e.key.toDouble(),
                  e.value.value,
                ))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= stats.history.length) {
                            return const SizedBox();
                          }
                          final month = stats.history[idx].month;
                          return Text(DateFormat('MM/yyyy').format(month),
                              style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: [
                        FlSpot(stats.history.length.toDouble(),
                            stats.forecastNextMonth),
                      ],
                      isCurved: false,
                      dotData: const FlDotData(show: true),
                      barWidth: 0,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'التوقع الشهري التالي: ${MoneyFormatter.format(stats.forecastNextMonth)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) =>
          const Center(child: Text('خطأ في تحميل بيانات التوقعات')),
    );
  }
}
