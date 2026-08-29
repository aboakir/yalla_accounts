// 📁 lib/features/employees/services/employee_ledger_service.dart

import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/finance/models/ledger_entry.dart';
import 'package:yalla_accounts/features/finance/services/ledger_database_service.dart';
import 'package:yalla_accounts/features/employees/models/salary.dart';

class EmployeeLedgerService {
  /// توليد قيد محاسبي عند صرف راتب موظف
  static Future<void> generateLedgerEntryFromSalary(Salary salary) async {
    final employeeName = salary.employeeName;
    final employeeId = salary.employeeId;
    final month = salary.month;
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final description = 'صرف راتب $employeeName عن شهر $month';

    /// 1. قيد الراتب المدفوع
    if (salary.paid > 0) {
      final entry = LedgerEntry(
        date: date,
        description: description,
        debitAccount: 'رواتب الموظفين',
        creditAccount: 'الصندوق',
        amount: salary.paid,
        referenceType: 'salary',
        referenceId: '$employeeId-$month',
        transactionType: 'صرف راتب',
        isApproved: true,
      );

      await LedgerDatabaseService.insertEntry(entry);
    }

    /// 2. قيد ذمم الرواتب إن وجد مستحق غير مدفوع
    if (salary.due > 0) {
      final entry = LedgerEntry(
        date: date,
        description: 'تسجيل ذمم على $employeeName عن راتب $month',
        debitAccount: 'رواتب الموظفين',
        creditAccount: 'ذمم رواتب',
        amount: salary.due,
        referenceType: 'salary',
        referenceId: '$employeeId-$month',
        transactionType: 'ذمم رواتب',
        isApproved: true,
      );

      await LedgerDatabaseService.insertEntry(entry);
    }
  }
}
