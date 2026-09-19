// 📁 lib/features/repairs/screens/repairs_and_ar_screen.dart
//
// شاشة الذمم + ملفات الإصلاح — نسخة احترافية بدون حذف أي وظيفة
// تحسينات:
// - تنظيم الكود بدون المساس بالمنطق
// - واجهة أنظف + أيقونات أوضح
// - لا RTL نهائياً
// - الحفاظ على recordPayment + RepairDetail
// - الحفاظ على الفلاتر والتصدير والإحصائيات كاملة

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yalla_accounts/core/platform/yalla_path_provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/finance/services/accounts_receivable_service.dart';
import 'package:yalla_accounts/features/finance/providers/pending_ar_provider.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

List<Repair> filterFinancialReceivables(
  List<Repair> source, {
  required bool insuranceTab,
  String search = '',
  String paymentStatus = 'الكل',
  DateTimeRange? dateRange,
}) {
  final needle = search.trim().toLowerCase();
  return source.where((repair) {
    final isInsurance = repair.beneficiaryType == 'شركة تأمين';
    if (insuranceTab != isInsurance) return false;
    final haystack =
        '${repair.beneficiaryName} ${repair.vehicleNumber} ${repair.vehicleType}'
            .toLowerCase();
    final matchesSearch = needle.isEmpty || haystack.contains(needle);
    final matchesStatus =
        paymentStatus == 'الكل' || repair.paymentStatus == paymentStatus;
    final matchesDate = dateRange == null ||
        (!repair.receivedDate.isBefore(dateRange.start) &&
            !repair.receivedDate.isAfter(dateRange.end));
    return matchesSearch && matchesStatus && matchesDate;
  }).toList(growable: false);
}

Map<String, int> financialReceivableStats(List<Repair> repairs) {
  final total = repairs.length;
  final paid = repairs.where((r) => r.paymentStatus == 'مسدد').length;
  final partial = repairs.where((r) => r.paymentStatus == 'مسدد جزئي').length;
  return {
    'المجموع': total,
    'مسدد': paid,
    'جزئي': partial,
    'غير مسدد': total - paid - partial,
  };
}

List<PieChartSectionData> financialReceivablePieSections(
  Map<String, int> stats,
) =>
    [
      PieChartSectionData(
        value: (stats['مسدد'] ?? 0).toDouble(),
        showTitle: false,
        radius: 28,
        color: AppColors.primary,
      ),
      PieChartSectionData(
        value: (stats['جزئي'] ?? 0).toDouble(),
        showTitle: false,
        radius: 28,
        color: Colors.orange,
      ),
      PieChartSectionData(
        value: (stats['غير مسدد'] ?? 0).toDouble(),
        showTitle: false,
        radius: 28,
        color: Colors.red,
      ),
    ];

class RepairsAndARScreen extends ConsumerStatefulWidget {
  const RepairsAndARScreen({super.key});

  @override
  ConsumerState<RepairsAndARScreen> createState() => _RepairsAndARScreenState();
}

class _RepairsAndARScreenState extends ConsumerState<RepairsAndARScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateTimeRange? _dateRange;
  String _search = '';
  String _statusFilter = 'الكل';
  final _df = DateFormat('yyyy-MM-dd');
  List<Repair> _allRepairs = [];
  bool _loadingRepairs = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
    _loadRepairs();
  }

  void _onTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadRepairs() async {
    final list = await RepairDatabaseService.getAllRepairs();
    setState(() {
      _allRepairs = list;
      _loadingRepairs = false;
    });
  }

  Future<void> _exportCsv(List<Map<String, dynamic>> rows) async {
    final sb = StringBuffer()..writeln('معرف,نوع,رقم,استلام,المتبقي,حالة');

    for (var r in rows) {
      sb.writeln(
          '${r['repairId']},${r['type']},${r['number']},${r['date']},${r['remaining']},${r['status']}');
    }

    final dir = await getDownloadsDirectory();
    final file = File('${dir!.path}/repairs_ar.csv');
    await file.writeAsString(sb.toString(), encoding: utf8);
    await Share.shareXFiles([XFile(file.path)], text: 'CSV ذمم المركبات');
  }

  void _showPaymentDialog(BuildContext context, WidgetRef ref, Repair r) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('سداد دفعة'),
        content: TextField(
          inputFormatters: const [YallaDigitNormalizer()],
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'المبلغ',
            hintText: '0.00',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text) ?? 0;
              final paidSoFar = await AccountsReceivableService.instance
                  .totalPaidForRepair(r.id.toString());
              if (!context.mounted) return;

              final remaining =
                  (r.totalFileValue - paidSoFar).clamp(0.0, double.infinity);

              if (amount <= 0 || amount > remaining) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('المبلغ غير صالح')));
                return;
              }

              await AccountsReceivableService.instance.recordPayment(
                repair: r,
                amount: amount,
                method: 'نقداً',
              );

              await _loadRepairs();
              if (!context.mounted) return;
              ref.invalidate(pendingArProvider);
              Navigator.pop(context);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  List<Repair> get _visibleRepairs => filterFinancialReceivables(
        _allRepairs,
        insuranceTab: _tabController.index == 1,
        search: _search,
        paymentStatus: _statusFilter,
        dateRange: _dateRange,
      );

  List<Repair> _filterList(List<Repair> list) {
    return list.where((r) {
      final comb = '${r.beneficiaryName} ${r.vehicleNumber} ${r.vehicleType}'
          .toLowerCase();

      final inSearch = _search.isEmpty || comb.contains(_search.toLowerCase());

      final inStatus =
          _statusFilter == 'الكل' || r.paymentStatus == _statusFilter;

      final inDate = _dateRange == null ||
          (!r.receivedDate.isBefore(_dateRange!.start) &&
              !r.receivedDate.isAfter(_dateRange!.end));

      return inSearch && inStatus && inDate;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final stats = financialReceivableStats(_visibleRepairs);

    return Scaffold(
      drawer:
          isDesktop ? null : const YallaSidebar(currentRoute: AppRoutes.debts),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: AppRoutes.debts),
            ),
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                    child: Column(children: [
                  _header(isDesktop),
                  _statsRow(stats),
                  _filters(),
                  _tabs(),
                ])),
              ],
              body: _loadingRepairs
                  ? const Center(child: CircularProgressIndicator())
                  : _tabViews(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- UI ----------------

  Widget _header(bool isDesktop) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: AdaptiveRow(
        children: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          const SizedBox(width: 8),
          const Text(
            'ذمم المركبات',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            onPressed: () {
              final rows = _filterList(_allRepairs).map((r) {
                final rem =
                    MoneyFormatter.format(r.totalFileValue - r.totalPaidAmount);
                return {
                  'repairId': r.id,
                  'type': r.vehicleType,
                  'number': r.vehicleNumber,
                  'date': _df.format(r.receivedDate),
                  'remaining': rem,
                  'status': r.paymentStatus,
                };
              }).toList();
              _exportCsv(rows);
            },
          ),
        ],
      ),
    );
  }

  Widget _statsRow(Map<String, int> stats) {
    final total = stats['المجموع'] ?? 0;
    final metrics = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _summaryMetric('المجموع', total, Colors.blue),
        _summaryMetric('مسدد', stats['مسدد'] ?? 0, AppColors.primary),
        _summaryMetric('جزئي', stats['جزئي'] ?? 0, Colors.orange),
        _summaryMetric('غير مسدد', stats['غير مسدد'] ?? 0, Colors.red),
      ],
    );
    final chartBlock = SizedBox(
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: total == 0
                ? const Center(child: Text('لا توجد بيانات'))
                : PieChart(
                    PieChartData(
                      sections: financialReceivablePieSections(stats),
                      centerSpaceRadius: 38,
                      sectionsSpace: 2,
                      startDegreeOffset: -90,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              _legendItem('مسدد', stats['مسدد'] ?? 0, total, AppColors.primary),
              _legendItem('جزئي', stats['جزئي'] ?? 0, total, Colors.orange),
              _legendItem(
                  'غير مسدد', stats['غير مسدد'] ?? 0, total, Colors.red),
            ],
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, box) => box.maxWidth < 560
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      metrics,
                      const SizedBox(height: 12),
                      Center(child: chartBlock)
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: metrics),
                      const SizedBox(width: 16),
                      chartBlock
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _summaryMetric(String title, int value, Color color) => Container(
        width: 112,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 11)),
            Text('$value',
                style: TextStyle(
                    color: color, fontSize: 19, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _legendItem(String label, int count, int total, Color color) {
    final percentage = total == 0 ? 0.0 : count * 100 / total;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$label $count (${percentage.toStringAsFixed(0)}%)',
            style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _filters() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                inputFormatters: const [YallaDigitNormalizer()],
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'بحث…',
                    border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _statusFilter,
              items: ['الكل', 'مسدد', 'مسدد جزئي', 'غير مسدد']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _statusFilter = v!),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(
                _dateRange == null
                    ? 'كل التواريخ'
                    : '${_df.format(_dateRange!.start)} → ${_df.format(_dateRange!.end)}',
              ),
              onPressed: () async {
                final dr = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (dr != null) setState(() => _dateRange = dr);
              },
            ),
          ],
        ),
      );

  Widget _tabs() => TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        tabs: const [
          Tab(text: 'أفراد'),
          Tab(text: 'تأمين'),
        ],
      );

  Widget _tabViews() => TabBarView(
        controller: _tabController,
        children: [
          _buildList(_filterList(_allRepairs
              .where((r) => r.beneficiaryType != 'شركة تأمين')
              .toList())),
          _buildList(_filterList(_allRepairs
              .where((r) => r.beneficiaryType == 'شركة تأمين')
              .toList())),
        ],
      );

  Widget _buildList(List<Repair> list) {
    if (list.isEmpty) return const Center(child: Text('لا توجد نتائج'));

    return RefreshIndicator(
      onRefresh: () async {
        await _loadRepairs();
        ref.invalidate(pendingArProvider);
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (ctx, i) {
          final r = list[i];
          return Slidable(
            key: ValueKey(r.id),
            startActionPane: ActionPane(
              motion: const DrawerMotion(),
              children: [
                SlidableAction(
                    onPressed: (_) => Navigator.pushNamed(
                        context, AppRoutes.repairDetail,
                        arguments: r),
                    backgroundColor: AppColors.primary,
                    icon: Icons.description,
                    label: 'تفاصيل')
              ],
            ),
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              children: [
                SlidableAction(
                    onPressed: (_) => _showPaymentDialog(context, ref, r),
                    backgroundColor: AppColors.primary,
                    icon: Icons.attach_money,
                    label: 'دفعة')
              ],
            ),
            child: _row(r),
          );
        },
      ),
    );
  }

  Widget _row(Repair r) {
    final remaining =
        (r.totalFileValue - r.totalPaidAmount).clamp(0.0, double.infinity);

    Color bg;
    if (r.paymentStatus == 'مسدد') {
      bg = AppColors.lightGreen;
    } else if (r.paymentStatus == 'مسدد جزئي') {
      bg = Colors.orange.shade100;
    } else {
      bg = Colors.red.shade100;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: AdaptiveRow(
        children: [
          const Icon(Icons.directions_car, size: 30, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.beneficiaryName} — ${r.vehicleNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('استلام: ${_df.format(r.receivedDate)}'),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('متبقي: ${MoneyFormatter.format(remaining)}'),
              Text('حالة: ${r.paymentStatus}'),
            ],
          ),
        ],
      ),
    );
  }
}
