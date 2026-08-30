import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

/// GLService — واجهة خفيفة لقيود: سلفة موظف + مكافأة موظف.
/// ملاحظة:
/// - الاستحقاق والصرف للرواتب صار عبر PayrollDatabaseService (وليس هنا).
/// - هذه الدوال تكتب gl_entries + gl_lines بتوازن صحيح.
/// - party_type='EMPLOYEE' و party_id=employeeId.
/// - method: 'cash' أو أي شيء بنكي (bank/transfer/cheque…).

class GLService {
  static bool _isBank(String? m) {
    final s = (m ?? '').toLowerCase();
    return s.contains('bank') ||
        s.contains('transfer') ||
        s.contains('cheque') ||
        s.contains('check') ||
        s.contains('visa') ||
        s.contains('master') ||
        s.contains('بطاقة') ||
        s.contains('شيك') ||
        s.contains('تحويل');
  }

  static Future<int> _ensure(
      String code, String name, String type, String nb) async {
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
        code: code, name: name, type: type, normalBalance: nb);
  }

  /// قيد سلفة موظف:
  /// Dr 1120.E<employeeId> سلف الموظف / Cr 1000 أو 1010
  static Future<int> recordEmployeeAdvance({
    required String employeeId,
    required double amount,
    String? method,
    DateTime? date,
    String? note,
  }) async {
    final amt = double.parse(max(0, amount).toStringAsFixed(2));
    if (amt <= 0) throw ArgumentError('amount must be > 0');

    final drAdv = await _ensure(
      '1120.E$employeeId',
      'سلف موظف - $employeeId',
      'ASSET',
      'DEBIT',
    );
    final crCashBank = await _ensure(
      _isBank(method) ? '1010' : '1000',
      _isBank(method) ? 'البنك' : 'الصندوق',
      'ASSET',
      'DEBIT',
    );

    final id = const Uuid().v4();
    return DBService.postEntryGL(
      date: date ?? DateTime.now(),
      ref: employeeId,
      source: 'EMP_ADV',
      sourceId: id,
      note: note ?? 'سلفة موظف',
      lines: [
        {
          'account_id': drAdv,
          'debit': amt,
          'credit': 0.0,
          'party_type': 'EMPLOYEE',
          'party_id': employeeId,
          'invoice_id': null,
          'repair_id': null,
        },
        {
          'account_id': crCashBank,
          'debit': 0.0,
          'credit': amt,
          'party_type': null,
          'party_id': null,
          'invoice_id': null,
          'repair_id': null,
        },
      ],
    );
  }

  /// قيد مكافأة موظف:
  /// Dr 5100 مصروف رواتب  / Cr 1000 الصندوق أو 1010 البنك
  /// نستخدم 5100 لأنّه الموجود في DBService كـ "مصروف رواتب".
  static Future<int> recordEmployeeBonus({
    required String employeeId,
    required double amount,
    String? method,
    DateTime? date,
    String? note,
  }) async {
    final amt = double.parse(max(0, amount).toStringAsFixed(2));
    if (amt <= 0) throw ArgumentError('amount must be > 0');

    final drExp = await _ensure('5100', 'مصروف رواتب', 'EXPENSE', 'DEBIT');
    final crCashBank = await _ensure(
      _isBank(method) ? '1010' : '1000',
      _isBank(method) ? 'البنك' : 'الصندوق',
      'ASSET',
      'DEBIT',
    );

    final id = const Uuid().v4();
    return DBService.postEntryGL(
      date: date ?? DateTime.now(),
      ref: employeeId,
      source: 'EMP_BONUS',
      sourceId: id,
      note: note ?? 'مكافأة موظف',
      lines: [
        {
          'account_id': drExp,
          'debit': amt,
          'credit': 0.0,
          'party_type': 'EMPLOYEE',
          'party_id': employeeId,
          'invoice_id': null,
          'repair_id': null,
        },
        {
          'account_id': crCashBank,
          'debit': 0.0,
          'credit': amt,
          'party_type': null,
          'party_id': null,
          'invoice_id': null,
          'repair_id': null,
        },
      ],
    );
  }
}
