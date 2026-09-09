import 'package:yalla_accounts/features/employees/models/salary.dart';

/// Legacy parallel ledger commands are disabled. Accrual uses payroll_runs and
/// payments use official vouchers, both posted into the main General Ledger.
class EmployeeLedgerService {
  static Future<void> generateLedgerEntryFromSalary(Salary salary) async {
    throw StateError(
        'استخدم استحقاق الرواتب وسند الصرف؛ إنشاء قيد رواتب مستقل غير مسموح.');
  }
}
