// 📁 lib/features/employees/screens/attendance_report_screen.dart
//
// AttendanceReportScreen — تقرير الحضور والغياب الشهري
// ---------------------------------------------------------------
// يعتمد على AttendanceDatabaseService.getAllAttendance() ثم يفلتر بالواجهة.
// فلاتر: الشهر (Month Picker) + EmployeeId (اختياري) + الحالة (الكل/حاضر/غائب).
// KPIs: إجمالي الأيام، الحضور، الغياب، نسبة الالتزام.
// عرض متكيف: DataTable على الديسكتوب وبطاقات على الموبايل.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';

class AttendanceReportScreen extends ConsumerStatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  ConsumerState<AttendanceReportScreen> createState() =>
      _AttendanceReportScreenState();
}

class _AttendanceReportScreenState
    extends ConsumerState<AttendanceReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _employeeId = '';
  String _status = 'all'; // all | present | absent

  bool _loading = true;
  String? _error;
  List<Attendance> _all = [];

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
      final rows = await AttendanceDatabaseService.getAllAttendance();
      rows.sort((a, b) => b.date.compareTo(a.date));
      setState(() => _all = rows);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // تحويل الحالة إلى صيغة موحدة للمقارنة
  // present: 'present' | 'حاضر'
  // absent : 'absent'  | 'غياب' | 'غائب'
  String _normalizeStatus(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('present') || s.contains('حاضر')) return 'present';
    if (s.contains('absent') || s.contains('غياب') || s.contains('غائب')) {
      return 'absent';
    }
    return s; // كما هي لو كانت قيم خاصة أخرى
  }

  // النص العربي المعروض حسب الحالة الموحّدة
  String _statusLabel(String norm) {
    switch (norm) {
      case 'present':
        return 'حاضر';
      case 'absent':
        return 'غائب';
      default:
        return norm; // حالة مخصّصة
    }
  }

  List<Attendance> get _filtered {
    return _all.where((a) {
      // فلترة الشهر
      final ym = DateFormat('yyyy-MM').format(a.date);
      if (ym != _yyyyMm) return false;

      // فلترة الموظف
      if (_employeeId.trim().isNotEmpty && a.employeeId != _employeeId.trim()) {
        return false;
      }

      // فلترة الحالة
      if (_status != 'all') {
        final norm = _normalizeStatus(a.status);
        if (norm != _status) return false;
      }
      return true;
    }).toList();
  }

  int get _presentCount =>
      _filtered.where((x) => _normalizeStatus(x.status) == 'present').length;
  int get _absentCount =>
      _filtered.where((x) => _normalizeStatus(x.status) == 'absent').length;
  int get _total => _filtered.length;
  double get _rate => _total == 0 ? 0 : (_presentCount / _total) * 100;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      drawer: isDesktop ? null : const Drawer(child: YallaSidebar()),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(
          workshopName:
              'تقرير الحضور والغياب - ${DateFormat('MMMM yyyy', 'ar').format(_month)}',
          showThemeToggle: true,
          actions: [
            IconButton(
              tooltip: 'اختر شهر',
              onPressed: _pickMonth,
              icon: const Icon(Icons.calendar_month),
            ),
          ],
        ),
      ),
      body: Row(
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

  // ---------------- Filters ----------------
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
              decoration: const InputDecoration(
                labelText: 'الشهر',
                border: OutlineInputBorder(),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('MMMM yyyy', 'ar').format(_month)),
                  const Icon(Icons.calendar_today, size: 18),
                ],
              ),
            ),
          ),
        ),
        // الحالة
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String>(
            value: _status,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('الكل')),
              DropdownMenuItem(value: 'present', child: Text('حاضر')),
              DropdownMenuItem(value: 'absent', child: Text('غائب')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'all'),
            decoration: const InputDecoration(
              labelText: 'الحالة',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        // Employee ID اختياري
        SizedBox(
          width: 220,
          child: TextField(
            onChanged: (v) => setState(() => _employeeId = v),
            decoration: const InputDecoration(
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

  // ---------------- KPIs ----------------
  Widget _kpis() {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _kpi('إجمالي الأيام', _total.toDouble(), Colors.black87),
        _kpi('أيام الحضور', _presentCount.toDouble(), Colors.green),
        _kpi('أيام الغياب', _absentCount.toDouble(), Colors.red),
        _kpi('نسبة الالتزام %', _rate, Colors.blue, bold: true, suffix: '%'),
      ],
    );
  }

  Widget _kpi(String label, double v, Color c,
      {bool bold = false, String suffix = ''}) {
    final val = v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    return Chip(
      label: Text('$label: $val$suffix',
          style: TextStyle(
            color: c,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          )),
      side: BorderSide(color: c.withOpacity(0.35)),
      backgroundColor: c.withOpacity(0.07),
    );
  }

  // ---------------- Mobile Cards ----------------
  Widget _cards(List<Attendance> rows) {
    final df = DateFormat('yyyy-MM-dd');
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final a = rows[i];
        final norm = _normalizeStatus(a.status);
        final isPresent = norm == 'present';
        final color = isPresent ? Colors.green : Colors.red;
        final icon = isPresent ? Icons.check : Icons.close;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          title: Text('الموظف ${a.employeeId} — ${_statusLabel(norm)}'),
          subtitle: Text(df.format(a.date)),
          trailing: Text(a.checkIn != null && a.checkOut != null
              ? '${a.checkIn} → ${a.checkOut}'
              : '—'),
        );
      },
    );
  }

  // ---------------- Desktop Table ----------------
  Widget _table(List<Attendance> rows) {
    final df = DateFormat('yyyy-MM-dd');
    final dataRows = rows.map((a) {
      final norm = _normalizeStatus(a.status);
      final isPresent = norm == 'present';
      final color = isPresent ? Colors.green : Colors.red;
      return DataRow(cells: [
        DataCell(Text(a.employeeId)),
        DataCell(Text(df.format(a.date))),
        DataCell(Text(_statusLabel(norm), style: TextStyle(color: color))),
        DataCell(Text(a.checkIn != null && a.checkOut != null
            ? '${a.checkIn} → ${a.checkOut}'
            : '—')),
        DataCell(Text(
            a.hoursWorked != null ? a.hoursWorked!.toStringAsFixed(2) : '—')),
        DataCell(Text(a.notes ?? '—')),
      ]);
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Employee ID')),
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('الدوام')),
          DataColumn(label: Text('ساعات العمل')),
          DataColumn(label: Text('ملاحظات')),
        ],
        rows: dataRows,
      ),
    );
  }
}
