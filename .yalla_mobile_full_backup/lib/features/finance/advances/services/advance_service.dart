// 📁 lib/features/finance/advances/services/advance_service.dart
//
// AdvanceService — سلفة موظف: Dr سلف موظفين / Cr نقد أو بنك.
// ينشر GL عبر DBService.postEntryGL ويربط party EMPLOYEE.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/accounting_gl.dart';

class AdvanceService {
  // أكواد من GL
  static const String _ACC_EMP_ADV_CODE = GL.empAdvances; // 1120
  static const String _ACC_CASH_CODE = GL.cash; // 1000
  static const String _ACC_BANK_CODE = GL.bank; // 1010

  static Future<int?> _acc(DatabaseExecutor db, String code) async {
    final r = await db.query('accounts',
        columns: ['id'], where: 'code=?', whereArgs: [code], limit: 1);
    if (r.isEmpty) return null;
    final v = r.first['id'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// ينشر قيد سلفة.
  /// method: 'نقد' أو أي من {تحويل، بنك، بطاقة، فيزا، ماستر، شيك} للبنك.
  static Future<int> postEmployeeAdvance({
    required String employeeId,
    required DateTime date,
    required double amount,
    String? ref,
    String method = 'نقد',
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');

    final db = await DBService.database;

    final advanceCode = '$_ACC_EMP_ADV_CODE.E$employeeId';
    final accAdv = await DBService.getAccountIdByCode(advanceCode) ??
        await DBService.ensureAccount(
          code: advanceCode,
          name: 'سلف موظف - $employeeId',
          type: 'ASSET',
          normalBalance: 'DEBIT',
        );
    final accCash = await _acc(db, _ACC_CASH_CODE);
    final accBank = await _acc(db, _ACC_BANK_CODE);
    if (accCash == null || accBank == null) {
      throw StateError(
          'أكواد 1000/1010 غير موجودة. نفّذ GL.ensureCoreAccounts.');
    }

    final isBank = {'تحويل', 'بنك', 'بطاقة', 'فيزا', 'ماستر', 'شيك'}
        .contains(method.trim());
    final creditAcc = isBank ? accBank : accCash;

    return DBService.postEntryGL(
      date: date,
      ref: ref,
      source: 'ADVANCE',
      sourceId: ref ?? 'ADV-${date.millisecondsSinceEpoch}',
      note: note,
      lines: [
        {
          'account_id': accAdv,
          'debit': amount,
          'credit': 0.0,
          'party_type': 'EMPLOYEE',
          'party_id': employeeId,
        },
        {
          'account_id': creditAcc,
          'debit': 0.0,
          'credit': amount,
          'party_type': null,
          'party_id': null,
        },
      ],
    );
  }
}
