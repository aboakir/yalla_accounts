// 📁 lib/features/employees/screens/reports/payroll_report_screen.dart
//
// PayrollReportScreen — تقرير الرواتب الشهرية (Snapshots)
// - يعتمد على SalaryDatabaseService.getSalariesByMonth(yyyy-MM).
// - فلتر بالشهر (Month Picker) + بحث EmployeeId (اختياري).
// - أعمدة snapshot: base/advance/total/paid/due.
// - عرض متكيّف: DataTable على الديسكتوب وبطاقات على الموبايل.
// - إضافة: أزرار شهر سابق/لاحق + تصدير CSV.

import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/employees/services/salary_database_service.dart';
import 'package:yalla_accounts/features/employees/models/salary.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PayrollReportScreen extends ConsumerStatefulWidget {
  const PayrollReportScreen({super.key});

  @override
  ConsumerState<PayrollReportScreen> createState() =>
      _PayrollReportScreenState();
}

class _PayrollReportScreenState extends ConsumerState<PayrollReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _employeeId = '';

  bool _loading = true;
  String? _error;
  List<Salary> _all = [];

  String get _yyyyMm => DateFormat('yyyy-MM').format(_month);

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(_month.year - 3, 1, 1),
      lastDate: DateTime(_month.year + 1, 12, 31),
      helpText: 'اختر شهر التقرير',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month, 1));
      await _loadMonth();
    }
  }

  Future<void> _loadMonth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SalaryDatabaseService.getSalariesByMonth(_yyyyMm);
      rows.sort((a, b) {
        final an = (a.employeeName ?? '').toLowerCase();
        final bn = (b.employeeName ?? '').toLowerCase();
        final n = an.compareTo(bn);
        return n != 0 ? n : a.employeeId.compareTo(b.employeeId);
      });
      setState(() => _all = rows);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Salary> get _filtered {
    final q = _employeeId.trim();
    if (q.isEmpty) return _all;
    return _all.where((s) => s.employeeId == q).toList();
  }

  double get _sumTotal => _filtered.fold(0.0, (s, x) => s + x.total);
  double get _sumPaid => _filtered.fold(0.0, (s, x) => s + x.paid);
  double get _sumDue => _filtered.fold(0.0, (s, x) => s + x.due);

  Future<void> _prevMonth() async {
    setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
    await _loadMonth();
  }

  Future<void> _nextMonth() async {
    setState(() => _month = DateTime(_month.year, _month.month + 1, 1));
    await _loadMonth();
  }

  Future<void> _exportPayrollCsv() async {
    final rows = _filtered;
    final b = StringBuffer(
        'employeeName,employeeId,month,base,advance,total,paid,due,date\n');
    for (final s in rows) {
      b.writeln([
        (s.employeeName ?? s.employeeId).replaceAll(',', ' '),
        s.employeeId,
        s.month ?? _yyyyMm,
        s.base.toStringAsFixed(2),
        s.advance.toStringAsFixed(2),
        s.total.toStringAsFixed(2),
        s.paid.toStringAsFixed(2),
        s.due.toStringAsFixed(2),
        DateFormat('yyyy-MM-dd').format(s.date),
      ].join(','));
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/payroll_$_yyyyMm.csv');
    await file.writeAsString(b.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء الملف: ${file.path}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      drawer: isDesktop ? null : const Drawer(child: YallaSidebar()),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(
          workshopName:
              'تقرير الرواتب - ${DateFormat('MMMM yyyy', 'ar').format(_month)}',
          showThemeToggle: true,
          actions: [
            IconButton(
              tooltip: 'الشهر السابق',
              onPressed: _prevMonth,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'اختر شهر',
              onPressed: _pickMonth,
              icon: const Icon(Icons.calendar_month),
            ),
            IconButton(
              tooltip: 'الشهر التالي',
              onPressed: _nextMonth,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'تصدير CSV',
              onPressed: _exportPayrollCsv,
              icon: const Icon(Icons.download),
            ),
          ],
        ),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const SizedBox(width: 260, child: YallaSidebar()),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMonth,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _filters(),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    Center(child: Text('خطأ: $_error'))
                  else ...[
                    _kpis(),
                    const Divider(),
                    if (_filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('لا توجد بيانات لهذا الشهر')),
                      )
                    else
                      (isDesktop ? _table(_filtered) : _cards(_filtered)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        // الشهر
        SizedBox(
          width: 240,
          child: InkWell(
            onTap: _pickMonth,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'الشهر',
                border: OutlineInputBorder(),
              ),
              child: AdaptiveRow(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('MMMM yyyy', 'ar').format(_month)),
                  const Icon(Icons.calendar_today, size: 18),
                ],
              ),
            ),
          ),
        ),
        // EmployeeId اختياري
        SizedBox(
          width: 220,
          child: TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            onChanged: (v) => setState(() => _employeeId = v),
            decoration: InputDecoration(
              labelText: 'Employee ID (اختياري)',
              hintText: 'فلترة حسب الموظف',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        // تحديث
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _loadMonth,
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث'),
          ),
        ),
      ],
    );
  }

  Widget _kpis() {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _kpi('إجمالي المستحق', _sumTotal, Colors.black87),
        _kpi('المدفوع', _sumPaid, Colors.green),
        _kpi('المتبقي', _sumDue, Colors.blue, bold: true),
      ],
    );
  }

  Widget _kpi(String label, double v, Color c, {bool bold = false}) {
    return Chip(
      label: Text(
        '$label: ${MoneyFormatter.format(v)}',
        style: TextStyle(
            color: c, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      side: BorderSide(color: c.withOpacity(0.35)),
      backgroundColor: c.withOpacity(0.07),
    );
  }

  Widget _cards(List<Salary> rows) {
    final df = DateFormat('yyyy-MM-dd');
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final s = rows[i];
        final leadingChar = (s.employeeName?.isNotEmpty == true
                ? s.employeeName!
                : s.employeeId)
            .substring(0, 1);
        return ListTile(
          leading: CircleAvatar(child: Text(leadingChar)),
          title: Text(s.employeeName ?? s.employeeId),
          subtitle: Text([
            'المستحق: ${MoneyFormatter.format(s.total)}',
            'المدفوع: ${MoneyFormatter.format(s.paid)}',
            'المتبقي: ${MoneyFormatter.format(s.due)}',
            'تاريخ: ${df.format(s.date)}',
          ].join('  •  ')),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(s.month ?? _yyyyMm),
              Text('ID: ${s.employeeId}'),
            ],
          ),
        );
      },
    );
  }

  Widget _table(List<Salary> rows) {
    final dataRows = rows.map((s) {
      return DataRow(cells: [
        DataCell(Text(s.employeeName ?? s.employeeId)),
        DataCell(Text(s.employeeId)),
        DataCell(Text(s.month ?? _yyyyMm)),
        DataCell(Text('${MoneyFormatter.format(s.base)}')),
        DataCell(Text('${MoneyFormatter.format(s.advance)}')),
        DataCell(Text('${MoneyFormatter.format(s.total)}')),
        DataCell(Text('${MoneyFormatter.format(s.paid)}')),
        DataCell(Text('${MoneyFormatter.format(s.due)}')),
        DataCell(Text(DateFormat('yyyy-MM-dd').format(s.date))),
      ]);
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columns: const [
          DataColumn(label: Text('Employee Name')),
          DataColumn(label: Text('Employee ID')),
          DataColumn(label: Text('Month')),
          DataColumn(label: Text('Base')),
          DataColumn(label: Text('Advance Applied')),
          DataColumn(label: Text('Total (Net)')),
          DataColumn(label: Text('Paid')),
          DataColumn(label: Text('Due')),
          DataColumn(label: Text('Date')),
        ],
        rows: dataRows,
      ),
    );
  }
}
