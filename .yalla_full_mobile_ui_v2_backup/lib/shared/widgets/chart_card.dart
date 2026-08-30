import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

enum ChartType { pie, bar, line }

class ChartCard extends StatelessWidget {
  final String title;
  final ChartType chartType;
  final Map<String, double> data;

  const ChartCard({
    super.key,
    required this.title,
    required this.chartType,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 220,
        maxWidth: 480,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : Colors.grey).withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            _ChartArea(chartType: chartType, data: data),
          ],
        ),
      ),
    );
  }
}

class _ChartArea extends StatelessWidget {
  final ChartType chartType;
  final Map<String, double> data;

  const _ChartArea({required this.chartType, required this.data});

  @override
  Widget build(BuildContext context) {
    final items = data.entries.toList();
    final sum = data.values.fold<double>(0, (a, b) => a + b);

    if (items.isEmpty || sum <= 0) {
      return const _EmptyChartPlaceholder();
    }

    // ✅ منع الـ infinite size:
    // - Pie: نسبة 1:1 داخل Box بقياس مضبوط
    // - Bar/Line: ارتفاع ثابت + تمدّد بعرض الحاوية
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final size = maxW.clamp(200.0, 420.0);

        switch (chartType) {
          case ChartType.pie:
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: size,
                  maxHeight: size,
                  minWidth: 200,
                  minHeight: 200,
                ),
                child: const AspectRatio(
                  aspectRatio: 1,
                  child: _PieChartContainer(),
                ),
              ),
            );
          case ChartType.bar:
            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 260),
              child: _BarChartWidget(items: items),
            );
          case ChartType.line:
            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 260),
              child: _LineChartWidget(items: items),
            );
        }
      },
    );
  }
}

class _EmptyChartPlaceholder extends StatelessWidget {
  const _EmptyChartPlaceholder();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 200,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232323) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
      ),
      child: Text(
        'لا توجد بيانات للعرض',
        style: TextStyle(
          color: isDark ? Colors.white70 : Colors.black54,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ---------- Pie Chart (بحجم مضبوط) ----------
class _PieChartContainer extends StatelessWidget {
  const _PieChartContainer();

  List<Color> get _palette => [
        AppColors.primary,
        Colors.orange,
        Colors.teal,
        Colors.indigo,
        Colors.pinkAccent,
        Colors.amber,
        Colors.cyan,
        Colors.deepPurple,
      ];

  @override
  Widget build(BuildContext context) {
    // نقرأ البيانات من الأب (_ChartArea) عبر InheritedWidget بسيطة
    final inherited = _ChartData.of(context);
    final items = inherited.items;
    final sum = inherited.sum;

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      final percent = (e.value / sum) * 100.0;
      final color = _palette[i % _palette.length];

      sections.add(
        PieChartSectionData(
          value: e.value,
          title: '${percent.toStringAsFixed(1)}%',
          radius: 50,
          showTitle: true,
          titleStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          color: color,
        ),
      );
    }

    return _ChartData(
      items: items,
      sum: sum,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 36,
          sections: sections,
          pieTouchData: PieTouchData(enabled: true),
        ),
      ),
    );
  }
}

// ---------- Bar Chart ----------
class _BarChartWidget extends StatelessWidget {
  final List<MapEntry<String, double>> items;
  const _BarChartWidget({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          barGroups: List.generate(items.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: items[i].value,
                  width: 16,
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= items.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      items[idx].key,
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 36),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Line Chart ----------
class _LineChartWidget extends StatelessWidget {
  final List<MapEntry<String, double>> items;
  const _LineChartWidget({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (items.length - 1).toDouble(),
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              spots: List.generate(
                items.length,
                (i) => FlSpot(i.toDouble(), items[i].value),
              ),
              barWidth: 3,
              color: AppColors.primary,
              dotData: const FlDotData(show: true),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= items.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      items[idx].key,
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 36),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipRoundedRadius: 8,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inherited لتبادل بيانات الشارت داخليًا (لـ Pie)
class _ChartData extends InheritedWidget {
  final List<MapEntry<String, double>> items;
  final double sum;

  const _ChartData({
    required super.child,
    required this.items,
    required this.sum,
  });

  static _ChartData of(BuildContext context) {
    final res = context.dependOnInheritedWidgetOfExactType<_ChartData>();
    assert(res != null, 'Chart data not found in context.');
    return res!;
  }

  @override
  bool updateShouldNotify(_ChartData oldWidget) =>
      oldWidget.items != items || oldWidget.sum != sum;
}
