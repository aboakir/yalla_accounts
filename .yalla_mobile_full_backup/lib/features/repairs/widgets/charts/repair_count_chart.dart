import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class RepairCountChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const RepairCountChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final List<BarChartGroupData> barGroups = [];
    final List<String> labels = [];
    int i = 0;

    for (var item in data) {
      final label = item['month'] ?? '';
      final value = (item['repairCount'] ?? 0) * 1.0;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(toY: value, width: 14, color: AppColors.info),
          ],
        ),
      );
      labels.add(label);
      i++;
    }

    return SizedBox(
      height: 250,
      child: BarChart(
        BarChartData(
          barGroups: barGroups,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      index < labels.length ? labels[index] : '',
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true),
            ),
          ),
        ),
      ),
    );
  }
}
