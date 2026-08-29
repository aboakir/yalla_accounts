// 📁 lib/features/employees/services/payroll_service.dart
//
// PayrollService — طبقة رقيقة فوق PayrollDatabaseService
// - نفس الواجهات: accrue / pay / listByEmployee / getById
// - تحسينات إدخال:
//   • تقريب القيم المالية لخانتي عشرية.
//   • رفض مبالغ غير صالحة.
//   • تطبيع method إلى قيم معروفة.
//   • NEW: جعل advanceApplied اختياريًا لتمكين التطبيق التلقائي للسلف عند عدم تمريره.
//
// ملاحظة: فحص قفل الشهر يتم في provider/الشاشة، وليس هنا.

import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';

class PayrollService {
  // --- Helpers ---
  static double _r(double v) => double.parse(v.toStringAsFixed(2));

  static String? _normalizeMethod(String? m) {
    if (m == null) return null;
    final s = m.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.contains('bank')) return 'bank';
    if (s.contains('transfer') || s.contains('تحويل')) return 'transfer';
    if (s.contains('cheque') || s.contains('check') || s.contains('شيك')) {
      return 'cheque';
    }
    return 'cash'; // الافتراضي
  }

  // إنشاء استحقاق
  static Future<String> accrue({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime accrualDate,
    required double gross,
    double allowances = 0,
    double deductions = 0,
    double?
        advanceApplied, // ⬅️ اختياري: إن كان null تُطبَّق السلف تلقائيًا في DB layer
    String? method,
    String? note,
  }) {
    final g = _r(gross);
    final a = _r(allowances);
    final d = _r(deductions);
    final adv = advanceApplied == null ? null : _r(advanceApplied);

    if (g <= 0) {
      throw ArgumentError('gross must be > 0');
    }
    if (a < 0 || d < 0 || (adv != null && adv < 0)) {
      throw ArgumentError('negative values are not allowed');
    }

    return PayrollDatabaseService.accrue(
      employeeId: employeeId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      accrualDate: accrualDate,
      gross: g,
      allowances: a,
      deductions: d,
      advanceApplied: adv,
      method: _normalizeMethod(method),
      note: note,
    );
  }

  // دفع كامل/جزئي
  static Future<void> pay({
    required String runId,
    required double amount,
    required DateTime date,
    String? method,
    String? note,
  }) {
    final v = _r(amount);
    if (v <= 0) {
      throw ArgumentError('amount must be > 0');
    }

    return PayrollDatabaseService.pay(
      runId: runId,
      amount: v,
      date: date,
      method: _normalizeMethod(method),
      note: note,
    );
  }

  // ==== إضافات مفيدة للـ UI ====

  /// جلب كل الاستحقاقات لموظف
  static Future<List<PayrollRun>> listByEmployee(String employeeId) {
    return PayrollDatabaseService.listByEmployee(employeeId);
  }

  /// جلب استحقاق واحد
  static Future<PayrollRun?> getById(String runId) {
    return PayrollDatabaseService.getById(runId);
  }
}
