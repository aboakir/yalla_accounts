// 📁 lib/features/home/widgets/overview_charts.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/home/widgets/operations_distribution_chart.dart';

class OverviewCharts extends StatelessWidget {
  final bool distributionOnly;
  const OverviewCharts({super.key, required this.distributionOnly});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'الرسوم البيانية التحليلية',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 24),
        const _ChartCard(title: 'توزيع العمليات حسب النوع', child: _PieChart()),
        if (!distributionOnly) ...[
          const SizedBox(height: 24),
          const _ChartCard(title: 'الإيرادات الشهرية', child: _BarChart()),
          const SizedBox(height: 24),
          const _ChartCard(title: 'عدد الفواتير الشهرية', child: _LineChart()),
          const SizedBox(height: 20),
          const OperationsDistributionChart(),
        ],
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 16),
          SizedBox(height: 200, child: child),
        ],
      ),
    );
  }
}

class _PieChart extends StatelessWidget {
  const _PieChart();

  @override
  Widget build(BuildContext context) {
    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: 50,
            color: AppColors.primary,
            title: 'إصلاح',
            titleStyle: _sectionTextStyle,
          ),
          PieChartSectionData(
            value: 30,
            color: Colors.blueAccent,
            title: 'فواتير',
            titleStyle: _sectionTextStyle,
          ),
          PieChartSectionData(
            value: 20,
            color: Colors.orangeAccent,
            title: 'قطع',
            titleStyle: _sectionTextStyle,
          ),
        ],
        sectionsSpace: 2,
        centerSpaceRadius: 32,
      ),
    );
  }

  TextStyle get _sectionTextStyle => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      );
}

class _BarChart extends StatelessWidget {
  const _BarChart();

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        maxY: 12000,
        barGroups: [
          _barGroup(1, 7000, AppColors.primary),
          _barGroup(2, 9000, Colors.blueAccent),
          _barGroup(3, 6000, Colors.orangeAccent),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) => Text(
                ['يناير', 'فبراير', 'مارس'][value.toInt() - 1],
                style: const TextStyle(fontSize: 12),
                textDirection: TextDirection.rtl,
              ),
              reservedSize: 32,
            ),
          ),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  BarChartGroupData _barGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          width: 18,
          color: color,
          borderRadius: BorderRadius.circular(4),
        )
      ],
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart();

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 50,
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(1, 10),
              FlSpot(2, 25),
              FlSpot(3, 30),
              FlSpot(4, 40),
            ],
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withOpacity(0.15),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, _) {
                const labels = ['يناير', 'فبراير', 'مارس', 'أبريل'];
                return Text(
                  labels[value.toInt() - 1],
                  style: const TextStyle(fontSize: 12),
                  textDirection: TextDirection.rtl,
                );
              },
            ),
          ),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}
