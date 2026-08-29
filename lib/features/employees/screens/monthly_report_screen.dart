// 📁 lib/features/employees/screens/monthly_report_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/providers/salary_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class MonthlyReportScreen extends ConsumerStatefulWidget {
  final Employee employee;

  const MonthlyReportScreen({super.key, required this.employee});

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<AttendanceReport> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = _generateReport();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'اختيار الشهر',
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        selectedMonth = DateTime(picked.year, picked.month);
        _reportFuture = _generateReport();
      });
    }
  }

  Future<AttendanceReport> _generateReport() async {
    final from = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final to = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    final totalWorkDays = to.difference(from).inDays + 1;

    // جلب الحضور
    final records = await AttendanceDatabaseService.getAttendanceForEmployee(
      employeeId: widget.employee.id,
      from: from,
      to: to,
    );

    // حساب الراتب عبر SalaryProvider
    await ref.read(salaryProvider.notifier).calculateSalaryFromAttendance(
          employeeId: widget.employee.id,
          baseSalary: widget.employee.baseSalary,
          totalWorkDaysInMonth: totalWorkDays,
          attendanceRecords: records,
        );
    final netSalary =
        ref.read(salaryProvider.notifier).getSalary(widget.employee.id);

    return AttendanceReport(
      workDays: records.where((r) => r.status == 'حضور').length,
      totalDays: totalWorkDays,
      salary: netSalary,
      attendance: records,
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'ar').format(selectedMonth);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('تقرير شهري'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'اختيار الشهر',
            onPressed: _pickMonth,
          ),
        ],
      ),
      body: FutureBuilder<AttendanceReport>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${snapshot.error}'));
          }
          final report = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('اسم الموظف: ${widget.employee.fullName}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text('الشهر: $monthLabel',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
                Expanded(child: _buildDetailsTable(report.attendance)),
                const SizedBox(height: 16),
                Text(
                  'صافي الراتب: ${MoneyFormatter.format(report.salary)}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailsTable(List<Attendance> records) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: MaterialStateColor.resolveWith(
            (_) => AppColors.primary.withOpacity(0.1)),
        columns: const [
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('دخول')),
          DataColumn(label: Text('خروج')),
          DataColumn(label: Text('الساعات')),
          DataColumn(label: Text('ملاحظات')),
        ],
        rows: records.map((r) {
          return DataRow(
            cells: [
              DataCell(Text(DateFormat('yyyy-MM-dd').format(r.date))),
              DataCell(Text(r.status)),
              DataCell(Text(r.checkIn ?? '—')),
              DataCell(Text(r.checkOut ?? '—')),
              DataCell(Text(r.hoursWorked.toString())),
              DataCell(Text(r.notes ?? '')),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class AttendanceReport {
  final int workDays;
  final int totalDays;
  final double salary;
  final List<Attendance> attendance;

  AttendanceReport({
    required this.workDays,
    required this.totalDays,
    required this.salary,
    required this.attendance,
  });
}
