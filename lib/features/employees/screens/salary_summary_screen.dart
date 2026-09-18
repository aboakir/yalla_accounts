// 📁 lib/features/employees/screens/salary_summary_screen.dart
//
// SalarySummaryScreen — ملخص رواتب شهري (من payroll_runs)
// - اختيار شهر (YYYY-MM)
// - KPIs: إجمالي المثبت، المدفوع، المتبقي، عدد الاستحقاقات، عدد المدفوعة بالكامل
// - جدول مفصل لكل موظف خلال الشهر: employee_id | net | paid | remain | status
//
// SQL (SQLite):
//   SELECT employee_id,
//          ROUND(SUM(net), 2)    AS net_sum,
//          ROUND(SUM(amount_paid), 2) AS paid_sum,
//          ROUND(SUM(net - amount_paid), 2) AS remain_sum,
//          MIN(status) AS any_status
//   FROM payroll_runs
//   WHERE strftime('%Y-%m', period_start) = ?
//   GROUP BY employee_id
//
// KPIs الإجمالية من نفس المصدر.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class SalarySummaryScreen extends StatefulWidget {
  const SalarySummaryScreen({super.key});

  @override
  State<SalarySummaryScreen> createState() => _SalarySummaryScreenState();
}

class _SalarySummaryScreenState extends State<SalarySummaryScreen> {
  String _ym = DateFormat('yyyy-MM').format(DateTime.now());
  bool _loading = true;
  String? _error;

  // تفاصيل مجمّعة لكل موظف
  List<Map<String, Object?>> _rows = [];
  // KPIs
  double _kNet = 0, _kPaid = 0, _kRemain = 0;
  int _kRuns = 0, _kFullyPaid = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final start = DateTime(now.year - 3, 1, 1);
    final end = DateTime(now.year + 1, 12, 31);
    final picked = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: end,
      initialDate: DateTime.parse('$_ym-01'),
      helpText: 'اختر أي يوم ضمن الشهر',
    );
    if (picked != null) {
      final newYm = DateFormat('yyyy-MM').format(picked);
      setState(() => _ym = newYm);
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
      _kNet = _kPaid = _kRemain = 0;
      _kRuns = _kFullyPaid = 0;
    });
    try {
      final db = await DBService.database;

      // تفاصيل لكل موظف
      final rows = await db.rawQuery('''
        SELECT employee_id,
               ROUND(SUM(net), 2)              AS net_sum,
               ROUND(SUM(amount_paid), 2)      AS paid_sum,
               ROUND(SUM(net - amount_paid), 2) AS remain_sum,
               SUM(CASE WHEN status='PAID' THEN 1 ELSE 0 END) AS paid_count,
               COUNT(*) AS runs_count
        FROM payroll_runs
        WHERE strftime('%Y-%m', period_start) = ?
        GROUP BY employee_id
        ORDER BY employee_id COLLATE NOCASE ASC;
      ''', [_ym]);

      // KPIs إجمالية
      final kpi = await db.rawQuery('''
        SELECT
          ROUND(SUM(net), 2)                 AS k_net,
          ROUND(SUM(amount_paid), 2)         AS k_paid,
          ROUND(SUM(net - amount_paid), 2)   AS k_remain,
          COUNT(*)                           AS k_runs,
          SUM(CASE WHEN status='PAID' THEN 1 ELSE 0 END) AS k_paid_runs
        FROM payroll_runs
        WHERE strftime('%Y-%m', period_start) = ?;
      ''', [_ym]);

      if (kpi.isNotEmpty) {
        _kNet = (kpi.first['k_net'] as num?)?.toDouble() ?? 0.0;
        _kPaid = (kpi.first['k_paid'] as num?)?.toDouble() ?? 0.0;
        _kRemain = (kpi.first['k_remain'] as num?)?.toDouble() ?? 0.0;
        _kRuns = (kpi.first['k_runs'] as int?) ?? 0;
        _kFullyPaid = (kpi.first['k_paid_runs'] as int?) ?? 0;
      }

      setState(() => _rows = rows);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/employees/salary-summary')),
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(workshopName: 'ملخص الرواتب', actions: []),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/employees/salary-summary'),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        AdaptiveRow(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _pickMonth,
                              icon: const Icon(Icons.calendar_month),
                              label: Text(_ym),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                final ym = DateFormat('yyyy-MM')
                                    .format(DateTime.now());
                                setState(() => _ym = ym);
                                _load();
                              },
                              child: const Text('الشهر الحالي'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                final now = DateTime.now();
                                final prev =
                                    DateTime(now.year, now.month - 1, 1);
                                final ym = DateFormat('yyyy-MM').format(prev);
                                setState(() => _ym = ym);
                                _load();
                              },
                              child: const Text('الشهر السابق'),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              tooltip: 'تحديث',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_error != null)
                          Text('خطأ: $_error',
                              style: const TextStyle(color: Colors.red)),

                        // KPIs
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            _kpi('إجمالي صافي مثبت', _kNet,
                                color: Colors.blue, bold: true),
                            _kpi('إجمالي مدفوع', _kPaid,
                                color: AppColors.primary),
                            _kpi('إجمالي متبقي', _kRemain,
                                color: Colors.orange),
                            _kpiCount('عدد الاستحقاقات', _kRuns),
                            _kpiCount('عدد المدفوعة بالكامل', _kFullyPaid),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),

                        // Table
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: AdaptiveDataTable(
                            columns: const [
                              DataColumn(label: Text('الموظف ID')),
                              DataColumn(label: Text('صافي مثبت')),
                              DataColumn(label: Text('مدفوع')),
                              DataColumn(label: Text('متبقي')),
                              DataColumn(label: Text('Runs')),
                              DataColumn(label: Text('Paid Runs')),
                            ],
                            rows: _rows.map((m) {
                              final empId = (m['employee_id'] ?? '').toString();
                              final net =
                                  (m['net_sum'] as num?)?.toDouble() ?? 0.0;
                              final paid =
                                  (m['paid_sum'] as num?)?.toDouble() ?? 0.0;
                              final remain =
                                  (m['remain_sum'] as num?)?.toDouble() ?? 0.0;
                              final runs = (m['runs_count'] as int?) ?? 0;
                              final paidRuns = (m['paid_count'] as int?) ?? 0;

                              return DataRow(cells: [
                                DataCell(Text(empId)),
                                DataCell(Text(MoneyFormatter.format(net))),
                                DataCell(Text(MoneyFormatter.format(paid))),
                                DataCell(Text(MoneyFormatter.format(remain))),
                                DataCell(Text('$runs')),
                                DataCell(Text('$paidRuns')),
                              ]);
                            }).toList(),
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

  Widget _kpi(String label, double value, {Color? color, bool bold = false}) {
    final c = color ?? Colors.black87;
    return Chip(
      label: Text('$label: ${MoneyFormatter.format(value)}',
          style: TextStyle(
              color: c, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      side: BorderSide(color: c.withOpacity(0.3)),
      backgroundColor: c.withOpacity(0.06),
    );
  }

  Widget _kpiCount(String label, int value) {
    return Chip(
      label: Text('$label: $value',
          style: const TextStyle(
              color: Colors.purple, fontWeight: FontWeight.w600)),
      side: BorderSide(color: Colors.purple.withOpacity(0.3)),
      backgroundColor: Colors.purple.withOpacity(0.06),
    );
  }
}
