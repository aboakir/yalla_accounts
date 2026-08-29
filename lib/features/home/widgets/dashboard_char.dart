// 📁 lib/features/home/widgets/dashboard_chart.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class DashboardChart extends StatelessWidget {
  const DashboardChart({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'الإيرادات والمصروفات الأسبوعية',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث البيانات',
                  onPressed: () {
                    // 🔄 قابل للتوصيل بذكاء اصطناعي لاحقًا
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 1.8,
              child: LineChart(_buildChartData(textColor)),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildChartData(Color textColor) {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 500,
        verticalInterval: 1,
        getDrawingHorizontalLine: (value) => FlLine(
          color: Colors.grey.withOpacity(0.15),
          strokeWidth: 1,
        ),
        getDrawingVerticalLine: (value) => FlLine(
          color: Colors.grey.withOpacity(0.15),
          strokeWidth: 1,
        ),
      ),
      titlesData: FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (value, _) {
              const days = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];
              if (value.toInt() < 0 || value.toInt() > 6) {
                return const SizedBox();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  days[value.toInt()],
                  style: TextStyle(fontSize: 12, color: textColor),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 500,
            getTitlesWidget: (value, _) => Text(
              '${value.toInt()}',
              style: TextStyle(fontSize: 11, color: textColor),
            ),
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade300),
      ),
      minY: 0,
      lineBarsData: [
        // 📈 الإيرادات
        LineChartBarData(
          spots: const [
            FlSpot(0, 1200),
            FlSpot(1, 1500),
            FlSpot(2, 1800),
            FlSpot(3, 1700),
            FlSpot(4, 1600),
            FlSpot(5, 1900),
            FlSpot(6, 2000),
          ],
          isCurved: true,
          color: AppColors.primary,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: AppColors.primary.withOpacity(0.12),
          ),
        ),
        // 📉 المصروفات
        LineChartBarData(
          spots: const [
            FlSpot(0, 800),
            FlSpot(1, 900),
            FlSpot(2, 950),
            FlSpot(3, 1100),
            FlSpot(4, 1000),
            FlSpot(5, 1050),
            FlSpot(6, 1150),
          ],
          isCurved: true,
          color: Colors.redAccent,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.redAccent.withOpacity(0.12),
          ),
        ),
      ],
    );
  }
}
