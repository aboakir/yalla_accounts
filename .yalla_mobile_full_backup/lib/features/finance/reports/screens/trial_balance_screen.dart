// 📁 lib/features/finance/reports/screens/trial_balance_screen.dart
//
// TrialBalanceScreen — ميزان المراجعة (GL v29) — نسخة مستقرة ومبسطة.
// يعتمد على:
//   • reportsRangeProvider
//   • trialBalanceProvider
//
// واجهة موحّدة مع AppColors + YallaSidebar، وكل النص عربي.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/finance/reports/providers/reports_providers.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class TrialBalanceScreen extends ConsumerWidget {
  const TrialBalanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    final range = ref.watch(reportsRangeProvider);
    final rowsAsync = ref.watch(trialBalanceProvider);
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
                  context: context,
                  title: 'ميزان المراجعة',
                  child: _headerControls(
                    fromLabel: df.format(range.start),
                    toLabel: df.format(range.end),
                    onPrev: () => _shiftMonth(ref, range, -1),
                    onNext: () => _shiftMonth(ref, range, 1),
                    onToday: () => _setCurrentMonth(ref),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: rowsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, s) => _errorBox('خطأ في التحميل: $e'),
                    data: (rows) {
                      final totalDebit = rows.fold<double>(
                          0, (s, r) => s + _toD(r['total_debit']));
                      final totalCredit = rows.fold<double>(
                          0, (s, r) => s + _toD(r['total_credit']));

                      return Column(
                        children: [
                          _totalsStrip(totalDebit, totalCredit),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: AdaptiveDataTable(
                                  columns: const [
                                    DataColumn(label: Text('الكود')),
                                    DataColumn(label: Text('الحساب')),
                                    DataColumn(label: Text('النوع')),
                                    DataColumn(label: Text('مدين')),
                                    DataColumn(label: Text('دائن')),
                                    DataColumn(label: Text('رصيد')),
                                  ],
                                  rows: rows.map((r) {
                                    return DataRow(cells: [
                                      DataCell(
                                          Text((r['code'] ?? '').toString())),
                                      DataCell(
                                          Text((r['name'] ?? '').toString())),
                                      DataCell(
                                          Text((r['type'] ?? '').toString())),
                                      DataCell(
                                          Text(_fmt(_toD(r['total_debit'])))),
                                      DataCell(
                                          Text(_fmt(_toD(r['total_credit'])))),
                                      DataCell(Text(_fmt(_toD(r['balance'])))),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: AdaptiveRow(
                              children: [
                                const Spacer(),
                                Text(
                                    'المجموع مدين: ${_fmt(totalDebit)}  |  المجموع دائن: ${_fmt(totalCredit)}'),
                              ],
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

  // ===== UI helpers (functions فقط لتجنّب أخطاء تعريف) =====

  Widget _topBar({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SafeArea(
        bottom: false,
        child: AdaptiveRow(
          children: [
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () {
                  final hasDrawer = Scaffold.maybeOf(ctx)?.hasDrawer ?? false;
                  if (hasDrawer) Scaffold.of(ctx).openDrawer();
                },
              ),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            child,
          ],
        ),
      ),
    );
  }

  Widget _headerControls({
    required String fromLabel,
    required String toLabel,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required VoidCallback onToday,
  }) {
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text('$fromLabel → $toLabel',
              style: const TextStyle(color: Colors.white)),
        ),
        IconButton(
          tooltip: 'الشهر السابق',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left, color: Colors.white),
        ),
        IconButton(
          tooltip: 'الشهر التالي',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, color: Colors.white),
        ),
        TextButton.icon(
          onPressed: onToday,
          icon: const Icon(Icons.today, color: Colors.white),
          label:
              const Text('الشهر الحالي', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _totalsStrip(double totalDebit, double totalCredit) {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          _statChip('المجموع مدين', _fmt(totalDebit), Colors.blueGrey),
          _statChip('المجموع دائن', _fmt(totalCredit), Colors.deepPurple),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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

  // ===== Date range actions =====

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

  // ===== utils =====
  static double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static String _fmt(double v) => v.toStringAsFixed(2);
}
