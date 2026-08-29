// 📁 lib/features/repairs/screens/repair_analytics_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_stats_provider.dart';
import 'package:yalla_accounts/features/repairs/widgets/payment_status_pie_chart.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairAnalyticsScreen extends ConsumerWidget {
  const RepairAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    final totalRepairs = ref.watch(totalRepairsCountProvider);
    final totalValue = ref.watch(totalFileValueProvider);
    final totalPaid = ref.watch(totalPaidAmountProvider);
    final monthlySummary = ref.watch(monthlyRepairSummaryProvider);

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/repair-analytics')),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("تحليلات إصلاح المركبات",
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
                width: 260,
                child: YallaSidebar(currentRoute: '/repair-analytics')),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildKpiCard("عدد الملفات", totalRepairs),
                      _buildKpiCard("القيمة الكلية", totalValue, isMoney: true),
                      _buildKpiCard("المدفوع", totalPaid, isMoney: true),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const PaymentStatusPieChart(),
                  const SizedBox(height: 48),
                  Text("عدد الإصلاحات الشهرية",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 320,
                    child: monthlySummary.when(
                      data: (data) => BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          barTouchData: BarTouchData(enabled: true),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= data.length) {
                                    return const SizedBox();
                                  }
                                  return const SizedBox();
                                  const SideTitleWidget(
                                    axisSide: AxisSide
                                        .left, // أو AxisSide.bottom, AxisSide.top, AxisSide.right حسب السياق
                                    child: Text('المدفوع'),
                                  );
                                },
                              ),
                            ),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(
                                  showTitles: true, reservedSize: 30),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(
                              show: true, drawVerticalLine: false),
                          barGroups: [
                            for (int i = 0; i < data.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: (data[i]['repair_count'] as int?)
                                            ?.toDouble() ??
                                        0.0,
                                    width: 20,
                                    borderRadius: BorderRadius.circular(6),
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.primary,
                                        AppColors.accent
                                      ],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                  )
                                ],
                              )
                          ],
                        ),
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) =>
                          const Center(child: Text("خطأ في تحميل البيانات")),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, AsyncValue<dynamic> value,
      {bool isMoney = false}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      shadowColor: Colors.black26,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(24),
        width: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4))
          ],
        ),
        child: value.when(
          data: (v) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.black54)),
              const SizedBox(height: 10),
              Text(
                isMoney ? MoneyFormatter.format(v) : v.toString(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text("-",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
