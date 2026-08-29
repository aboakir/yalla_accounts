// 📁 lib/features/repairs/widgets/repair_summary_section.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class RepairSummarySection extends StatefulWidget {
  final List<Repair> repairs;

  const RepairSummarySection({super.key, required this.repairs});

  @override
  State<RepairSummarySection> createState() => _RepairSummarySectionState();
}

class _RepairSummarySectionState extends State<RepairSummarySection> {
  int? _touchedIndex;
  bool _showBarChart = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final paidCount = widget.repairs
        .where((r) => (r.paymentStatus ?? '').trim() == 'مسدد')
        .length
        .toDouble();
    final partialCount = widget.repairs
        .where((r) => (r.paymentStatus ?? '').trim() == 'مسدد جزئي')
        .length
        .toDouble();
    final unpaidCount = widget.repairs
        .where((r) => (r.paymentStatus ?? '').trim() == 'غير مسدد')
        .length
        .toDouble();
    final totalCount = paidCount + partialCount + unpaidCount;

    final totalValue =
        widget.repairs.fold<double>(0, (sum, r) => sum + r.fileValue);
    final totalPaid =
        widget.repairs.fold<double>(0, (sum, r) => sum + r.totalPaidAmount);
    final totalRemaining = (totalValue - totalPaid).clamp(0.0, totalValue);

    final isWide = MediaQuery.of(context).size.width >= 800;
    final formatter = NumberFormat.decimalPattern('en_US');

    if (totalCount == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'لا توجد بيانات كافية لعرض الإحصائيات',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // العنوان و مفتاح تبديل نوع الرسم
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📈 ملخص الإصلاحات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Row(
                  children: [
                    const Text('عرض بار'),
                    Switch(
                      value: _showBarChart,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() {
                          _touchedIndex = null;
                          _showBarChart = val;
                        });
                      },
                    ),
                    const Text('عرض دائري'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _showBarChart
                            ? _buildBarChart(
                                context, paidCount, partialCount, unpaidCount)
                            : _buildPieChart(context, theme, paidCount,
                                partialCount, unpaidCount, totalCount),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 300,
                        child: _buildFinancialSummary(
                          theme,
                          totalValue,
                          totalPaid,
                          totalRemaining,
                          paidCount,
                          partialCount,
                          unpaidCount,
                          totalCount,
                          formatter,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _showBarChart
                          ? _buildBarChart(
                              context, paidCount, partialCount, unpaidCount)
                          : _buildPieChart(context, theme, paidCount,
                              partialCount, unpaidCount, totalCount),
                      const SizedBox(height: 24),
                      _buildFinancialSummary(
                        theme,
                        totalValue,
                        totalPaid,
                        totalRemaining,
                        paidCount,
                        partialCount,
                        unpaidCount,
                        totalCount,
                        formatter,
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(BuildContext context, ThemeData theme, double paid,
      double partial, double unpaid, double total) {
    return Column(
      children: [
        SizedBox(
          height: 250,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 60,
                  sections: [
                    _makePieSection(
                        index: 0,
                        label: 'مسدد',
                        value: paid,
                        total: total,
                        color: Colors.green),
                    _makePieSection(
                        index: 1,
                        label: 'جزئي',
                        value: partial,
                        total: total,
                        color: Colors.orange),
                    _makePieSection(
                        index: 2,
                        label: 'غير مسدد',
                        value: unpaid,
                        total: total,
                        color: Colors.red),
                  ],
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            response?.touchedSection == null) {
                          _touchedIndex = null;
                        } else {
                          _touchedIndex =
                              response!.touchedSection!.touchedSectionIndex;
                        }
                      });
                    },
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('الإجمالي',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(
                    total.toInt().toString(),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            _buildLegendItem(
                color: Colors.green, label: 'مسدد ($paid)', index: 0),
            _buildLegendItem(
                color: Colors.orange, label: 'جزئي ($partial)', index: 1),
            _buildLegendItem(
                color: Colors.red, label: 'غير مسدد ($unpaid)', index: 2),
          ],
        ),
      ],
    );
  }

  PieChartSectionData _makePieSection({
    required int index,
    required String label,
    required double value,
    required double total,
    required Color color,
  }) {
    final isTouched = index == _touchedIndex;
    final radius = isTouched ? 70.0 : 55.0;
    final percentage = total > 0 ? (value / total * 100) : 0.0;
    return PieChartSectionData(
      color: color,
      value: value,
      radius: radius,
      title: '${percentage.toStringAsFixed(1)}%',
      titleStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      badgeWidget:
          isTouched ? _renderBadge(label, value.toInt().toString()) : null,
      badgePositionPercentageOffset: 1.1,
    );
  }

  Widget _renderBadge(String label, String count) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
          color: Colors.black87, borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          Text(count,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildBarChart(
      BuildContext context, double paid, double partial, double unpaid) {
    final dataMap = {
      'مسدد': paid,
      'جزئي': partial,
      'غير مسدد': unpaid,
    };
    final maxVal =
        dataMap.values.fold<double>(0, (prev, v) => v > prev ? v : prev);

    return SizedBox(
      height: 250,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BarChart(
            BarChartData(
              maxY: maxVal + (maxVal * 0.2),
              barGroups: dataMap.entries.map((entry) {
                final idx = dataMap.keys.toList().indexOf(entry.key);
                final isTouched = idx == _touchedIndex;
                return BarChartGroupData(x: idx, barRods: [
                  BarChartRodData(
                    toY: entry.value,
                    color: _colorForLabel(entry.key),
                    width: isTouched ? 22 : 18,
                    borderRadius: BorderRadius.circular(6),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxVal + (maxVal * 0.2),
                      color: Colors.grey[200]!,
                    ),
                  )
                ]);
              }).toList(),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) => Text(
                              val.toInt().toString(),
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black54),
                            ),
                        interval: maxVal / 4)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final labelIndex = val.toInt();
                      if (labelIndex >= 0 && labelIndex < dataMap.keys.length) {
                        final key = dataMap.keys.toList()[labelIndex];
                        return SideTitleWidget(
                          axisSide: meta.axisSide, // ✅ هذا السطر هو المطلوب
                          child:
                              Text(key, style: const TextStyle(fontSize: 12)),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        response?.spot == null) {
                      _touchedIndex = null;
                    } else {
                      _touchedIndex = response!.spot!.touchedBarGroupIndex;
                    }
                  });
                },
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorForLabel(String label) {
    switch (label) {
      case 'مسدد':
        return Colors.green;
      case 'جزئي':
        return Colors.orange;
      case 'غير مسدد':
        return Colors.red;
      default:
        return AppColors.primary;
    }
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required int index,
  }) {
    final isSelected = _touchedIndex == index;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isSelected ? 16 : 14,
          height: isSelected ? 16 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border:
                isSelected ? Border.all(color: Colors.black, width: 2) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: isSelected ? 14 : 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialSummary(
    ThemeData theme,
    double totalValue,
    double totalPaid,
    double totalRemaining,
    double paidCount,
    double partialCount,
    double unpaidCount,
    double totalCount,
    NumberFormat formatter,
  ) {
    final paidPercent = totalCount > 0 ? (paidCount / totalCount * 100) : 0.0;
    final partialPercent =
        totalCount > 0 ? (partialCount / totalCount * 100) : 0.0;
    final unpaidPercent =
        totalCount > 0 ? (unpaidCount / totalCount * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusCard(
          color: Colors.green,
          icon: Icons.check_circle,
          label: 'مسدد',
          count: paidCount.toInt(),
          percentage: paidPercent.toInt(),
        ),
        const SizedBox(height: 12),
        _StatusCard(
          color: Colors.orange,
          icon: Icons.remove_circle,
          label: 'جزئي',
          count: partialCount.toInt(),
          percentage: partialPercent.toInt(),
        ),
        const SizedBox(height: 12),
        _StatusCard(
          color: Colors.red,
          icon: Icons.error,
          label: 'غير مسدد',
          count: unpaidCount.toInt(),
          percentage: unpaidPercent.toInt(),
        ),
        const Divider(height: 32, color: Colors.grey),
        Text(
          'قيمة الملفات الكلية: ${MoneyFormatter.format(totalValue)}',
          style:
              theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'إجمالي المدفوعات: ${MoneyFormatter.format(totalPaid)}',
          style:
              theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'إجمالي الباقي: ${MoneyFormatter.format(totalRemaining)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: totalRemaining == 0 ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }
}

/// بطاقة عرض حالة دفعات (عدد، نسبة مئوية)
class _StatusCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final int count;
  final int percentage;

  const _StatusCard({
    required this.color,
    required this.icon,
    required this.label,
    required this.count,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.1),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$count",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
            const Spacer(),
            Text(
              "$percentage%",
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
