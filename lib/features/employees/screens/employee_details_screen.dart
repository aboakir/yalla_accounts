import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/release/release_scope_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/screens/edit_employee_screen.dart';
import 'package:yalla_accounts/features/employees/screens/edit_salary_screen.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/providers/salary_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class EmployeeDetailsScreen extends ConsumerWidget {
  final Employee employee;

  const EmployeeDetailsScreen({super.key, required this.employee});

  Future<double> _calculateNetSalary(
      WidgetRef ref, Employee employee, DateTime selectedMonth) async {
    final from = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final to = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    final totalDaysInMonth = to.difference(from).inDays + 1;

    final records = await AttendanceDatabaseService.getAttendanceForEmployee(
      employeeId: employee.id,
      from: from,
      to: to,
    );

    final calculated =
        await ref.read(salaryProvider.notifier).calculateAndReturn(
              employeeId: employee.id,
              baseSalary: employee.baseSalary,
              totalWorkDaysInMonth: totalDaysInMonth,
              attendanceRecords: records,
              periodStart: from,
              periodEnd: to,
            );

    return calculated;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final selectedMonth = DateTime.now();

    return FutureBuilder<double>(
      // حساب صافي الراتب
      future: _calculateNetSalary(ref, employee, selectedMonth),
      builder: (context, snapshot) {
        final salary = snapshot.data ?? employee.netSalary;

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            title: const Text('تفاصيل الموظف'),
            backgroundColor: AppColors.primary,
            actions: [
              IconButton(
                onPressed: () {
                  // فتح شاشة الرواتب مباشرة
                  Navigator.pushNamed(
                    context,
                    AppRoutes.employeePayroll, // ✅
                    arguments: employee,
                  );
                },
                icon: const Icon(Icons.payments),
                tooltip: 'الرواتب',
              ),
              if (ReleaseScopeConfig.employeeAdvancesEnabled)
                IconButton(
                  onPressed: () {
                    // Direct advances/rewards UI is deferred in the first beta.
                    Navigator.pushNamed(
                      context,
                      AppRoutes.employeeAdvances,
                      arguments: employee,
                    );
                  },
                  icon: const Icon(Icons.savings),
                  tooltip: 'السلف والمكافآت',
                ),
            ],
          ),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.all(16),
            child: AdaptiveRow(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('تعديل البيانات العامة'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              EditEmployeeScreen(employee: employee),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.money),
                    label: const Text('تعديل الراتب'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditSalaryScreen(employee: employee),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.payments),
                    label: const Text('الرواتب'),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.employeePayroll, // ✅
                        arguments: employee,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(employee, salary),
                      const SizedBox(height: 24),
                      isWide
                          ? AdaptiveRow(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildPersonalInfo(employee)),
                                const SizedBox(width: 16),
                                Expanded(
                                    child:
                                        _buildJobAndSalary(employee, salary)),
                              ],
                            )
                          : Column(
                              children: [
                                _buildPersonalInfo(employee),
                                const SizedBox(height: 16),
                                _buildJobAndSalary(employee, salary),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(Employee employee, double netSalary) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: AppColors.primary.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AdaptiveRow(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primary,
              child: Text(
                employee.fullName.isNotEmpty ? employee.fullName[0] : '?',
                style: const TextStyle(fontSize: 30, color: Colors.white),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.fullName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    employee.jobTitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('صافي الراتب', style: TextStyle(color: Colors.grey)),
                Text(
                  MoneyFormatter.format(netSalary),
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfo(Employee employee) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('البيانات الشخصية'),
            _infoRow('الاسم الكامل', employee.fullName),
            _infoRow('الرقم الوظيفي', employee.employeeCode),
            _infoRow('رقم الهاتف', employee.phone),
            _infoRow('البريد الإلكتروني', employee.email),
            _infoRow(
                'العنوان', employee.address.isEmpty ? '—' : employee.address),
            const SizedBox(height: 16),
            _sectionTitle('ملاحظات'),
            Text(
              employee.notes.isNotEmpty ? employee.notes : 'لا توجد ملاحظات',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobAndSalary(Employee employee, double netSalary) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('بيانات التوظيف'),
            _infoRow('المسمى الوظيفي', employee.jobTitle),
            _infoRow('الحالة', employee.status),
            _infoRow('طريقة الدفع', employee.paymentMethod),
            _infoRow('تاريخ التعيين',
                DateFormat('yyyy-MM-dd').format(employee.hireDate)),
            _infoRow('ساعات العمل يومياً', '${employee.hoursPerDay}'),
            _infoRow('أيام العمل بالأسبوع', '${employee.workDaysPerWeek}'),
            _infoRow(
                'السلفة الحالية', MoneyFormatter.format(employee.advances)),
            const SizedBox(height: 16),
            _sectionTitle('تفاصيل الراتب'),
            _infoRow(
                'الراتب الأساسي', MoneyFormatter.format(employee.baseSalary)),
            _infoRow('البدلات', MoneyFormatter.format(employee.allowances)),
            _infoRow('الخصومات', MoneyFormatter.format(employee.deductions)),
            _infoRow('صافي الراتب', MoneyFormatter.format(netSalary)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AdaptiveRow(
        children: [
          Expanded(
              flex: 4,
              child: Text('$label:', style: const TextStyle(fontSize: 14))),
          Expanded(
              flex: 6,
              child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
