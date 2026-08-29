// 📁 lib/features/employees/providers/advance_provider.dart
//
// AdvanceProvider — إدارة سلف/مكافآت/تسديدات الموظفين (DB + GL)
// --------------------------------------------------------------
// API:
// - loadAdvances(employeeId, {from,to,method})
// - addAdvance(advance, {method})
// - updateAdvance(advance, {method})
// - repayAdvance({...})
// - deleteAdvance(id, employeeId)
// - reverseAdvance(id, employeeId)
// - deleteAdvancesForEmployee(employeeId)
// - getPendingBalance(employeeId)
//
// ملاحظات:
// - تقريب القيم لخانتين.
// - تطبيع طريقة الدفع: cash | bank | transfer | cheque.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/employees/models/advance.dart';
import 'package:yalla_accounts/features/employees/services/advance_database_service.dart';

final advanceProvider =
    StateNotifierProvider<AdvanceNotifier, List<Advance>>((ref) {
  return AdvanceNotifier();
});

class AdvanceNotifier extends StateNotifier<List<Advance>> {
  AdvanceNotifier() : super(const []);

  // ===== Helpers =====
  double _r(double v) => double.parse(v.toStringAsFixed(2));
  String? _normalizeMethod(String? m) {
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

  /// تحميل سلف/مكافآت/تسديدات موظف مع فلاتر اختيارية
  Future<void> loadAdvances(
    String employeeId, {
    String? from, // 'yyyy-MM-dd'
    String? to, // 'yyyy-MM-dd'
    String? method,
  }) async {
    final rows = await AdvanceDatabaseService.listByEmployee(
      employeeId,
      from: from,
      to: to,
      method: method,
    );
    rows.sort((a, b) => b.date.compareTo(a.date)); // تنازلي
    state = List.unmodifiable(rows);
  }

  Future<double> getPendingBalance(String employeeId) {
    return AdvanceDatabaseService.pendingBalance(employeeId);
  }

  // ===== Commands =====

  /// إضافة سلفة أو مكافأة + نشر GL
  Future<void> addAdvance(Advance advance, {String? method}) async {
    final amt = _r(advance.amount);
    if (amt <= 0) throw ArgumentError('amount must be > 0');

    final normMethod = _normalizeMethod(method ?? advance.method);
    final fixed = advance.copyWith(amount: amt, method: normMethod);

    await AdvanceDatabaseService.insertAdvance(
      advance: fixed,
      method: normMethod,
    );

    await loadAdvances(advance.employeeId);
  }

  /// تعديل سلفة/مكافأة موجودة + عكس القيد القديم ثم إعادة نشره
  Future<void> updateAdvance(Advance advance, {String? method}) async {
    final amt = _r(advance.amount);
    if (amt <= 0) throw ArgumentError('amount must be > 0');

    final normMethod = _normalizeMethod(method ?? advance.method);
    final fixed = advance.copyWith(amount: amt, method: normMethod);

    await AdvanceDatabaseService.updateAdvance(
      advance: fixed,
      method: normMethod,
    );

    await loadAdvances(advance.employeeId);
  }

  /// تسديد سلفة نقدًا/بنك + GL + إنشاء سجل repayment
  Future<void> repayAdvance({
    required String employeeId,
    required double amount,
    String method = 'cash',
    DateTime? date,
    String? note,
  }) async {
    final v = _r(amount);
    if (v <= 0) throw ArgumentError('amount must be > 0');

    final d = date ?? DateTime.now();
    final normMethod = _normalizeMethod(method) ?? 'cash';

    await AdvanceDatabaseService.repayAdvanceCashBank(
      employeeId: employeeId,
      amount: v,
      method: normMethod,
      date: d,
      note: note,
    );

    await loadAdvances(employeeId);
  }

  /// حذف سجل واحد + عكس قيده
  Future<void> deleteAdvance(String id, String employeeId) async {
    await AdvanceDatabaseService.deleteAdvance(id);
    await loadAdvances(employeeId);
  }

  /// عكس القيد فقط دون حذف السجل
  Future<void> reverseAdvance(String id, String employeeId) async {
    await AdvanceDatabaseService.reverseAdvance(id);
    await loadAdvances(employeeId);
  }

  /// حذف كل سلف/مكافآت/تسديدات موظف + عكسها
  Future<void> deleteAdvancesForEmployee(String employeeId) async {
    await AdvanceDatabaseService.deleteByEmployee(employeeId);
    await loadAdvances(employeeId);
  }
}
