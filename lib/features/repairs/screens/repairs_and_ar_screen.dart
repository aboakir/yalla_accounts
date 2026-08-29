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
import 'package:path_provider/path_provider.dart';
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
    _tabController = TabController(length: 2, vsync: this);
    _loadRepairs();
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
              ref.invalidate(pendingArProvider);
              Navigator.pop(context);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  Map<String, int> get _stats {
    var total = _allRepairs.length;
    var paid = _allRepairs.where((r) => r.paymentStatus == 'مسدد').length;
    var partial =
        _allRepairs.where((r) => r.paymentStatus == 'مسدد جزئي').length;
    var unpaid = total - paid - partial;

    return {
      'المجموع': total,
      'مسدد': paid,
      'جزئي': partial,
      'غير مسدد': unpaid,
    };
  }

  List<PieChartSectionData> get _pieSections {
    final s = _stats;
    final total = s['المجموع']!.toDouble();

    return [
      PieChartSectionData(
          value: s['مسدد']!.toDouble(),
          title: 'مسدد ${(s['مسدد']! / total * 100).toStringAsFixed(0)}%',
          color: Colors.green),
      PieChartSectionData(
          value: s['جزئي']!.toDouble(),
          title: 'جزئي ${(s['جزئي']! / total * 100).toStringAsFixed(0)}%',
          color: Colors.orange),
      PieChartSectionData(
          value: s['غير مسدد']!.toDouble(),
          title: 'غير ${(s['غير مسدد']! / total * 100).toStringAsFixed(0)}%',
          color: Colors.red),
    ];
  }

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
    final stats = _stats;

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
            child: Column(
              children: [
                _header(isDesktop),
                _statsRow(stats),
                _filters(),
                _tabs(),
                Expanded(
                  child: _loadingRepairs
                      ? const Center(child: CircularProgressIndicator())
                      : _tabViews(),
                ),
              ],
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

  Widget _statsRow(Map<String, int> stats) => Padding(
        padding: const EdgeInsets.all(12),
        child: AdaptiveRow(
          children: [
            _statCard('المجموع', stats['المجموع']!, Colors.blue),
            const SizedBox(width: 8),
            _statCard('غير مسدد', stats['غير مسدد']!, Colors.red),
          ],
        ),
      );

  Widget _statCard(String title, int value, Color color) {
    return Expanded(
      child: Card(
        color: color.withOpacity(0.12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              Text(value.toString(),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(
                height: 70,
                child: PieChart(PieChartData(
                    sections: _pieSections,
                    centerSpaceRadius: 18,
                    sectionsSpace: 0)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: AdaptiveRow(
          children: [
            Expanded(
              child: TextField(
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
                    backgroundColor: Colors.green,
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
      bg = Colors.green.shade100;
    } else if (r.paymentStatus == 'مسدد جزئي')
      bg = Colors.orange.shade100;
    else
      bg = Colors.red.shade100;

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
