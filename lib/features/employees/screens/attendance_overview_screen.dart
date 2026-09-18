// 📁 lib/features/employees/screens/attendance_overview_screen.dart
//
// AttendanceOverviewScreen — عرض شهري لحضور موظف واحد
// مصدر البيانات: AttendanceDatabaseService + employeeProvider لِلائحة الموظفين
// بدون أي مزود attendanceProvider خارجي.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/providers/employee_provider.dart'
    show employeeProvider;
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class AttendanceOverviewScreen extends ConsumerStatefulWidget {
  const AttendanceOverviewScreen({super.key});

  @override
  ConsumerState<AttendanceOverviewScreen> createState() =>
      _AttendanceOverviewScreenState();
}

class _AttendanceOverviewScreenState
    extends ConsumerState<AttendanceOverviewScreen> {
  Employee? _selectedEmployee;
  DateTime _selectedMonth = DateTime.now();

  bool _loading = false;
  String? _error;
  List<Attendance> _records = const [];

  @override
  void initState() {
    super.initState();
    // لو في موظفين جاهزين بعد أول build بنحمّل تلقائي
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final emps = ref.read(employeeProvider).employees;
      if (emps.isNotEmpty) {
        setState(() => _selectedEmployee = emps.first);
        _loadAttendance();
      }
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'اختر تاريخ ضمن الشهر المطلوب',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _selectedMonth = picked);
      await _loadAttendance();
    }
  }

  Future<void> _loadAttendance() async {
    if (_selectedEmployee == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _records = const [];
    });
    try {
      final from = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final to = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final list = await AttendanceDatabaseService.getAttendanceForEmployee(
        employeeId: _selectedEmployee!.id,
        from: from,
        to: to,
      );
      setState(() => _records = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final empState = ref.watch(employeeProvider);
    final emps = empState.employees;

    // تأمين قيمة الموظف المختار لو تغيّرت اللائحة
    if (_selectedEmployee != null &&
        !emps.any((e) => e.id == _selectedEmployee!.id)) {
      _selectedEmployee = null;
      _records = const [];
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(
          workshopName: user?.name ?? '',
          logoPath: user?.workshopLogoPath ?? '',
          showThemeToggle: true,
          actions: const [],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AdaptiveRow(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Employee>(
                    decoration: const InputDecoration(
                      labelText: 'اختر الموظف',
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedEmployee,
                    items: emps
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e.fullName)))
                        .toList(),
                    onChanged: (e) async {
                      setState(() => _selectedEmployee = e);
                      await _loadAttendance();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(DateFormat('yyyy-MM').format(_selectedMonth)),
                  onPressed: _pickMonth,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loading ? null : _loadAttendance,
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (empState.isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (empState.error != null)
              Expanded(
                  child:
                      Center(child: Text('❌ خطأ الموظفين: ${empState.error}')))
            else if (emps.isEmpty)
              const Expanded(child: Center(child: Text('لا يوجد موظفون')))
            else if (_selectedEmployee == null)
              const Expanded(
                  child: Center(child: Text('اختر موظفًا لعرض الحضور')))
            else if (_error != null)
              Expanded(child: Center(child: Text('❌ خطأ: $_error')))
            else
              _buildAttendanceBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceBody() {
    final totalDays =
        DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month);
    final presentCount = _records.where((r) => r.status == 'حاضر').length;
    final absentCount = totalDays - presentCount;
    final percent =
        totalDays > 0 ? (presentCount / totalDays * 100).round() : 0;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdaptiveRow(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _kpi('أيام الحضور', '$presentCount', AppColors.primary),
              _kpi('أيام الغياب', '$absentCount', Colors.red),
              _kpi('% حضور', '$percent%', Colors.blue),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: AdaptiveDataTable(
                columns: const [
                  DataColumn(label: Text('التاريخ')),
                  DataColumn(label: Text('اليوم')),
                  DataColumn(label: Text('الحالة')),
                  DataColumn(label: Text('ملاحظات')),
                ],
                rows: List.generate(totalDays, (i) {
                  final day = DateTime(
                      _selectedMonth.year, _selectedMonth.month, i + 1);
                  final rec = _records.firstWhere(
                    (r) => _isSameDate(r.date, day),
                    orElse: () => Attendance(
                      employeeId: _selectedEmployee?.id ?? '',
                      date: day,
                      status: 'غائب',
                      id: '',
                    ),
                  );
                  return DataRow(cells: [
                    DataCell(Text(DateFormat('yyyy-MM-dd').format(day))),
                    DataCell(Text(DateFormat('EEEE', 'ar').format(day))),
                    DataCell(AdaptiveRow(
                      children: [
                        Icon(_iconForStatus(rec.status),
                            color: _colorForStatus(rec.status)),
                        const SizedBox(width: 6),
                        Text(rec.status),
                      ],
                    )),
                    DataCell(Text(rec.notes ?? '')),
                  ]);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String t, String v, Color c) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
            const SizedBox(height: 8),
            Text(v,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: c)),
          ],
        ),
      ),
    );
  }

  IconData _iconForStatus(String status) {
    switch (status) {
      case 'حاضر':
        return Icons.check_circle;
      case 'غائب':
        return Icons.cancel;
      case 'تأخير':
        return Icons.watch_later;
      case 'إجازة':
        return Icons.beach_access;
      case 'مغادرة':
        return Icons.exit_to_app;
      default:
        return Icons.help_outline;
    }
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case 'حاضر':
        return AppColors.primary;
      case 'غائب':
        return Colors.red;
      case 'تأخير':
        return Colors.orange;
      case 'إجازة':
        return Colors.blue;
      case 'مغادرة':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
