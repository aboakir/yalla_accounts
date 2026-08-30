// 📁 lib/features/finance/reports/screens/clients_aging_screen.dart
//
// ClientsAgingScreen — شاشة أعمار ذمم العملاء (GL v30)
// ----------------------------------------------------
// يعتمد على arAgingProvider + reportsRangeProvider من reports_providers.dart
// يعرض أعمار الذمم مجمعة حسب العميل (0–30 / 31–60 / 61–90 / 91–120 / +120)
// واجهة متناسقة مع AppColors و YallaSidebar.
// تصميم متجاوب يعمل على الموبايل والديسكتوب.
// ----------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/features/finance/reports/providers/reports_providers.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ClientsAgingScreen extends ConsumerWidget {
  const ClientsAgingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    final range = ref.watch(reportsRangeProvider);
    final asyncRows = ref.watch(arAgingProvider);
    final df = DateFormat('yyyy-MM-dd', 'ar');

    return Scaffold(
      drawer: isDesktop ? null : const Drawer(child: YallaSidebar()),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const SizedBox(width: 260, child: YallaSidebar()),
          Expanded(
            child: Column(
              children: [
                _topBar(
                  title: 'أعمار ذمم العملاء',
                  rangeText:
                      '${df.format(range.start)} → ${df.format(range.end)}',
                  onPrev: () => _shiftMonth(ref, range, -1),
                  onNext: () => _shiftMonth(ref, range, 1),
                  onToday: () => _setCurrentMonth(ref),
                ),
                const Divider(height: 1),
                Expanded(
                  child: asyncRows.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, s) => _errorBox('خطأ في تحميل البيانات:\n$e'),
                    data: (rows) {
                      final total = rows.fold<double>(
                          0, (s, r) => s + _toD(r['total_due']));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _summaryHeader(total),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: AdaptiveDataTable(
                                  columns: const [
                                    DataColumn(label: Text('العميل')),
                                    DataColumn(label: Text('النوع')),
                                    DataColumn(label: Text('0–30')),
                                    DataColumn(label: Text('31–60')),
                                    DataColumn(label: Text('61–90')),
                                    DataColumn(label: Text('91–120')),
                                    DataColumn(label: Text('+120')),
                                    DataColumn(label: Text('الإجمالي')),
                                  ],
                                  rows: rows.map((r) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text((r['client_name'] ?? '')
                                            .toString())),
                                        DataCell(Text((r['client_type'] ?? '')
                                            .toString())),
                                        DataCell(
                                            Text(_fmt(_toD(r['current'])))),
                                        DataCell(Text(_fmt(_toD(r['d30'])))),
                                        DataCell(Text(_fmt(_toD(r['d60'])))),
                                        DataCell(Text(_fmt(_toD(r['d90'])))),
                                        DataCell(Text(_fmt(_toD(r['over90'])))),
                                        DataCell(Text(
                                          _fmt(_toD(r['total_due'])),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold),
                                        )),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ======== Widgets helpers ========

  Widget _topBar({
    required String title,
    required String rangeText,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required VoidCallback onToday,
  }) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SafeArea(
        bottom: false,
        child: AdaptiveRow(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  Text(rangeText, style: const TextStyle(color: Colors.white)),
            ),
            IconButton(
              tooltip: 'السابق',
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left, color: Colors.white),
            ),
            IconButton(
              tooltip: 'التالي',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right, color: Colors.white),
            ),
            TextButton.icon(
              onPressed: onToday,
              icon: const Icon(Icons.today, color: Colors.white),
              label: const Text('الشهر الحالي',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryHeader(double total) {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(12),
      child: AdaptiveRow(
        children: [
          Text('إجمالي الذمم: ',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          Text(
            _fmt(total),
            style: const TextStyle(
                color: Colors.blueGrey, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  // ======== Logic helpers ========

  static void _shiftMonth(
      WidgetRef ref, ReportDateRange current, int deltaMonths) {
    final s =
        DateTime(current.start.year, current.start.month + deltaMonths, 1);
    final e = DateTime(current.start.year,
        current.start.month + deltaMonths + 1, 0, 23, 59, 59);
    ref.read(reportsRangeProvider.notifier).state =
        ReportDateRange(start: s, end: e);
  }

  static void _setCurrentMonth(WidgetRef ref) {
    ref.read(reportsRangeProvider.notifier).state =
        ReportDateRange.currentMonth();
  }

  static double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static String _fmt(double v) => v.toStringAsFixed(2);
}
