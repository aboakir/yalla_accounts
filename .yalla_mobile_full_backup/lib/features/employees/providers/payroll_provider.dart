// 📁 lib/features/employees/providers/payroll_provider.dart
//
// PayrollProvider — إدارة استحقاقات/دفعات الرواتب عبر PayrollService
// --------------------------------------------------------------
// • فحص قفل الشهر قبل الإنشاء.
// • تقريب مركزي لخانتين عشريتين.
// • تطبيع طريقة الدفع: cash | bank | transfer | cheque.
// • إعادة التحميل بعد كل عملية للحفاظ على الحالة محدثة.
// --------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/employees/services/payroll_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_periods_service.dart';

final payrollProvider =
    StateNotifierProvider<PayrollNotifier, List<PayrollRun>>((ref) {
  return PayrollNotifier();
});

class PayrollNotifier extends StateNotifier<List<PayrollRun>> {
  PayrollNotifier() : super(const []);

  // ===== Helpers =====
  double _r(double v) => double.parse(v.toStringAsFixed(2));

  String? _norm(String? m) {
    if (m == null) return null;
    final s = m.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.contains('bank')) return 'bank';
    if (s.contains('transfer') || s.contains('تحويل')) return 'transfer';
    if (s.contains('cheque') || s.contains('check') || s.contains('شيك')) {
      return 'cheque';
    }
    return 'cash';
  }

  // ===== Queries =====
  Future<void> load(String employeeId) async {
    final rows = await PayrollDatabaseService.listByEmployee(employeeId);
    rows.sort((a, b) => b.accrualDate.compareTo(a.accrualDate));
    state = List.unmodifiable(rows);
  }

  // ===== Commands =====
  Future<String> accrue({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime accrualDate,
    required double gross,
    double allowances = 0,
    double deductions = 0,
    double? advanceApplied, // إذا null يتم تطبيق السلف تلقائيًا داخل الخدمة
    String? method,
    String? note,
  }) async {
    // قفل الشهر
    final y = periodStart.year;
    final m = periodStart.month;
    if (await PayrollPeriodsService.isLocked(y, m)) {
      final mk =
          '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
      throw StateError('فترة $mk مقفلة. افتحها قبل إنشاء الاستحقاق.');
    }

    final runId = await PayrollService.accrue(
      employeeId: employeeId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      accrualDate: accrualDate,
      gross: _r(gross),
      allowances: _r(allowances),
      deductions: _r(deductions),
      advanceApplied: advanceApplied == null ? null : _r(advanceApplied),
      method: _norm(method),
      note: note,
    );

    await load(employeeId);
    return runId;
  }

  Future<void> pay({
    required String employeeId,
    required String runId,
    required double amount,
    required DateTime date,
    String? method,
    String? note,
  }) async {
    final v = _r(amount);
    if (v <= 0) throw ArgumentError('amount must be > 0');

    await PayrollService.pay(
      runId: runId,
      amount: v,
      date: date,
      method: _norm(method),
      note: note,
    );

    await load(employeeId);
  }
}
