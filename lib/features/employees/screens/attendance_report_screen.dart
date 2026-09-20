import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/providers/employee_provider.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/services/attendance_reporting_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class AttendanceReportScreen extends ConsumerStatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  ConsumerState<AttendanceReportScreen> createState() =>
      _AttendanceReportScreenState();
}

class _AttendanceReportScreenState
    extends ConsumerState<AttendanceReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _from;
  DateTime? _to;
  String? _employeeId;
  bool _loading = true;
  String? _error;
  AttendancePolicy? _policy;
  List<Attendance> _rawRows = const [];

  DateTime get _rangeFrom => _from ?? DateTime(_month.year, _month.month, 1);
  DateTime get _rangeTo => _to ?? DateTime(_month.year, _month.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AttendanceDatabaseService.getAllAttendance();
      final policy = await AttendancePolicy.fromWorkshopSettings();
      rows.sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        _rawRows = rows;
        _policy = policy;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AttendancePeriodReport? get _report {
    final employeeId = _employeeId;
    final policy = _policy;
    if (employeeId == null || policy == null) return null;
    return AttendanceReportingService.build(
      records: _rawRows,
      employeeId: employeeId,
      from: _rangeFrom,
      to: _rangeTo,
      policy: policy,
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(_month.year - 5, 1, 1),
      lastDate: DateTime(_month.year + 2, 12, 31),
      helpText: 'اختر شهر التقرير',
    );
    if (picked == null) return;
    setState(() {
      _month = DateTime(picked.year, picked.month, 1);
      _from = null;
      _to = null;
    });
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeFrom,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'من تاريخ',
    );
    if (picked == null) return;
    setState(() {
      _from = DateTime(picked.year, picked.month, picked.day);
      if (_rangeTo.isBefore(_rangeFrom)) _to = _from;
    });
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeTo,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'إلى تاريخ',
    );
    if (picked == null) return;
    setState(() {
      _to = DateTime(picked.year, picked.month, picked.day);
      if (_rangeTo.isBefore(_rangeFrom)) _from = _to;
    });
  }

  String _statusLabel(AttendanceReportDay day) {
    if (day.inferredAbsence) return 'غياب مستنتج';
    switch (day.status) {
      case AttendanceStatus.present:
        return 'حضور';
      case AttendanceStatus.absent:
        return 'غياب';
      case AttendanceStatus.paidLeave:
        return 'إجازة مدفوعة';
      case AttendanceStatus.unpaidLeave:
        return 'إجازة غير مدفوعة';
      case AttendanceStatus.holiday:
        return 'عطلة رسمية';
      default:
        return day.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeeState = ref.watch(employeeProvider);
    final employees = employeeState.employees;
    final knownIds = employees.map((e) => e.id).toSet();
    if (_employeeId == null && employees.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _employeeId == null) {
          setState(() => _employeeId = employees.first.id);
        }
      });
    } else if (_employeeId != null && !knownIds.contains(_employeeId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() =>
              _employeeId = employees.isEmpty ? null : employees.first.id);
        }
      });
    }

    final isDesktop = Responsive.isDesktop(context);
    final report = _report;
    return Scaffold(
      drawer: isDesktop ? null : const Drawer(child: YallaSidebar()),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(
          workshopName: 'سجل / كشف الحضور',
          showThemeToggle: true,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const SizedBox(width: 260, child: YallaSidebar()),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _filters(employees),
                  const SizedBox(height: 12),
                  if (_loading || employeeState.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    Center(child: Text('تعذر تحميل الحضور: $_error'))
                  else if (employees.isEmpty)
                    const _EmptyMessage('لا يوجد موظفون لعرض كشف الحضور')
                  else if (_employeeId == null || report == null)
                    const _EmptyMessage('اختر موظفًا لعرض كشف الحضور')
                  else ...[
                    _summary(report),
                    const SizedBox(height: 12),
                    if (report.days.isEmpty)
                      const _EmptyMessage('لا توجد بيانات ضمن الفترة المختارة')
                    else if (isDesktop)
                      _table(report)
                    else
                      _cards(report),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(List<Employee> employees) {
    final df = DateFormat('yyyy-MM-dd');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                value: _employeeId != null &&
                        employees.any((e) => e.id == _employeeId)
                    ? _employeeId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الموظف'),
                items: employees
                    .map((e) => DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(e.fullName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(growable: false),
                onChanged: (value) => setState(() => _employeeId = value),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickMonth,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(DateFormat('MMMM yyyy', 'ar').format(_month)),
            ),
            OutlinedButton.icon(
              onPressed: _pickFrom,
              icon: const Icon(Icons.first_page),
              label: Text('من ${df.format(_rangeFrom)}'),
            ),
            OutlinedButton.icon(
              onPressed: _pickTo,
              icon: const Icon(Icons.last_page),
              label: Text('إلى ${df.format(_rangeTo)}'),
            ),
            TextButton.icon(
              onPressed: () => setState(() {
                _from = null;
                _to = null;
              }),
              icon: const Icon(Icons.restart_alt),
              label: const Text('الشهر كاملًا'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(AttendancePeriodReport report) {
    Widget chip(String label, String value, Color color) => Chip(
          label: Text('$label: $value'),
          avatar: Icon(Icons.circle, size: 10, color: color),
          side: BorderSide(color: color.withOpacity(.3)),
        );

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        chip('أيام الحضور', '${report.presentDays}', AppColors.primary),
        chip('أيام الغياب', '${report.absentDays}', Colors.red),
        chip('إجمالي ساعات العمل', report.totalWorkedHours.toStringAsFixed(2),
            Colors.blue),
        chip('إجمالي التأخير', '${report.totalLateMinutes} دقيقة',
            Colors.orange),
        chip('الفترة', '${report.days.length} يوم', Colors.blueGrey),
      ],
    );
  }

  Widget _cards(AttendancePeriodReport report) {
    final df = DateFormat('EEEE، dd/MM/yyyy', 'ar');
    return Column(
      children: report.days.reversed.map((day) {
        final present = day.status == AttendanceStatus.present;
        final color = present
            ? AppColors.primary
            : day.status == AttendanceStatus.absent
                ? Colors.red
                : Colors.blueGrey;
        final details = <String>[
          if (day.checkIn?.isNotEmpty == true) 'حضور ${day.checkIn}',
          if (day.checkOut?.isNotEmpty == true) 'انصراف ${day.checkOut}',
          if (day.workedHours > 0) '${day.workedHours.toStringAsFixed(2)} ساعة',
          if (day.lateMinutes > 0) 'تأخير ${day.lateMinutes} د',
        ];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(.12),
              foregroundColor: color,
              child: Icon(present ? Icons.check : Icons.event_note),
            ),
            title: Text(df.format(day.date)),
            subtitle: details.isEmpty ? null : Text(details.join(' • ')),
            trailing: Text(
              _statusLabel(day),
              textAlign: TextAlign.left,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _table(AttendancePeriodReport report) {
    final df = DateFormat('yyyy-MM-dd');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columns: const [
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('الحضور')),
          DataColumn(label: Text('الانصراف')),
          DataColumn(label: Text('ساعات العمل')),
          DataColumn(label: Text('التأخير')),
          DataColumn(label: Text('ملاحظات')),
        ],
        rows: report.days.reversed
            .map((day) => DataRow(cells: [
                  DataCell(Text(df.format(day.date))),
                  DataCell(Text(_statusLabel(day))),
                  DataCell(Text(day.checkIn ?? '—')),
                  DataCell(Text(day.checkOut ?? '—')),
                  DataCell(Text(day.workedHours.toStringAsFixed(2))),
                  DataCell(Text(
                      day.lateMinutes == 0 ? '—' : '${day.lateMinutes} د')),
                  DataCell(Text(day.notes ??
                      (day.inferredAbsence
                          ? 'لا يوجد سجل لليوم المجدول'
                          : '—'))),
                ]))
            .toList(growable: false),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ),
    );
  }
}
