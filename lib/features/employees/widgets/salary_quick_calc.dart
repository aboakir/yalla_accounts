import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/providers/salary_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

/// يعرض حوار "الراتب المحسوب" لشهر محدد اعتمادًا على الحضور.
/// يعتمد على salary_provider + attendance_database_service المعدّلين.
Future<void> showMonthlySalaryQuickCalc({
  required BuildContext context,
  required WidgetRef ref,
  required Employee employee,
  required DateTime month, // أي يوم داخل الشهر المطلوب
  bool payOfficialHolidays = true, // فعّلها إذا العطل مدفوعة عندك
}) async {
  // ثبّت بداية ونهاية الشهر
  final from = DateTime(month.year, month.month, 1);
  final to = DateTime(month.year, month.month + 1, 0);
  final totalDaysInMonth = to.difference(from).inDays + 1;

  // احضر سجلات الحضور
  final records = await AttendanceDatabaseService.getAttendanceForEmployee(
    employeeId: employee.id,
    from: from,
    to: to,
  );

  // حساب الراتب الموحّد
  final net = await ref.read(salaryProvider.notifier).calculateAndReturn(
        employeeId: employee.id,
        baseSalary: employee.baseSalary,
        totalWorkDaysInMonth: totalDaysInMonth,
        attendanceRecords: records,
        payOfficialHolidays: payOfficialHolidays,
      );

  // عرض النتيجة
  final formatted = net.toStringAsFixed(2);
  // تجاهل إن كان الراتب الأساسي صفر
  final warnBase = employee.baseSalary <= 0;

  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('الراتب المحسوب'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('راتب ${employee.fullName} هو: ${MoneyFormatter.format(net)}'),
          const SizedBox(height: 8),
          Text('الشهر: ${from.year}-${from.month.toString().padLeft(2, '0')}'),
          if (warnBase) ...[
            const SizedBox(height: 12),
            const Text(
              'تنبيه: الراتب الأساسي = 0. حدّث بيانات الموظف.',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسنًا')),
      ],
    ),
  );
}
