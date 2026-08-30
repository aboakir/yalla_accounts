// -----------------------------------------------------------------------------
// 📁 lib/features/home/screens/dashboard/widgets/monthly_pie_chart.dart
// FINAL — Pie Chart + Side Text (No Overflow)
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class MonthlyPieChart extends StatelessWidget {
  final double income;
  final double expenses;
  final double profit;

  const MonthlyPieChart({
    super.key,
    required this.income,
    required this.expenses,
    required this.profit,
  });

  String _format(num v) {
    final f = NumberFormat("#,###.##", "ar");
    return f.format(v);
  }

  @override
  Widget build(BuildContext context) {
    final total = income.abs() + expenses.abs() + profit.abs();

    if (total == 0) {
      return const Center(
        child: Text(
          "لا توجد بيانات مالية لهذا الشهر",
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final incomePercent = (income.abs() / total) * 100;
    final expensesPercent = (expenses.abs() / total) * 100;
    final profitPercent = (profit.abs() / total) * 100;

    return SizedBox(
      height: 260,
      child: AdaptiveRow(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ------------------------------------------------------------
          // LEFT SIDE — TEXTS (LEGEND)
          // ------------------------------------------------------------
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "الدخل: ${_format(income)}",
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "المصاريف: ${_format(expenses)}",
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF9800),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  profit >= 0
                      ? "الربح: +${_format(profit)}"
                      : "الخسارة: -${_format(profit.abs())}",
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: profit >= 0
                        ? Colors.orange.shade800
                        : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // ------------------------------------------------------------
          // RIGHT SIDE — PIE CHART
          // ------------------------------------------------------------
          Expanded(
            flex: 1,
            child: PieChart(
              PieChartData(
                startDegreeOffset: -90,
                centerSpaceRadius: 55,
                sectionsSpace: 2,
                sections: [
                  PieChartSectionData(
                    value: income.abs(),
                    title: "${incomePercent.toStringAsFixed(1)}%",
                    color: Colors.green,
                    radius: 60,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  PieChartSectionData(
                    value: expenses.abs(),
                    title: "${expensesPercent.toStringAsFixed(1)}%",
                    color: Colors.red,
                    radius: 60,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  PieChartSectionData(
                    value: profit.abs(),
                    title: "${profitPercent.toStringAsFixed(1)}%",
                    color: const Color(0xFFFF9800),
                    radius: 60,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
