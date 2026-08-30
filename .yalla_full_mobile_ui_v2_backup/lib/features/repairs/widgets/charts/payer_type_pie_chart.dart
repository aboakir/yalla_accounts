import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class PayerTypePieChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const PayerTypePieChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final List<PieChartSectionData> sections = [];

    double total =
        data.fold(0, (sum, item) => sum + (item['totalRevenue'] ?? 0));

    for (var item in data) {
      final payerType = item['payerType'] ?? 'غير محدد';
      final value = (item['totalRevenue'] ?? 0) * 1.0;
      final percentage = total > 0 ? (value / total) * 100 : 0;

      final color = payerType == "تأمين"
          ? AppColors.primary
          : payerType == "أفراد"
              ? AppColors.warning
              : AppColors.lightGrey;

      sections.add(
        PieChartSectionData(
          title: '${percentage.toStringAsFixed(1)}%',
          value: value,
          color: color,
          radius: 60,
          titleStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    return SizedBox(
      height: 250,
      child: PieChart(
        PieChartData(
          sections: sections,
          centerSpaceRadius: 40,
          sectionsSpace: 2,
        ),
      ),
    );
  }
}
