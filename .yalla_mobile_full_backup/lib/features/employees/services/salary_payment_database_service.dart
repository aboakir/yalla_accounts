// 📁 lib/features/employees/services/salary_payment_database_service.dart
//
// SalaryPaymentDatabaseService — ربط الرواتب بالـ GL مباشرة
// القيد الواحد:
//   Dr 5000 مصروف رواتب = base + allowances - deductions
//   Cr 1300 سلف الموظفين = advances
//   Cr 1000/1010 نقد/بنك  = totalPaid
//
// يعتمد DB v29.
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/accounting_gl.dart';
import 'package:yalla_accounts/features/employees/models/salary_payment.dart';

class SalaryPaymentDatabaseService {
  static const String _table = 'salary_payments';
  static Future<Database> get _db async => DBService.database;

  // ================= Schema =================
  static Future<void> ensureTable() async {
    final db = await _db;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          id TEXT PRIMARY KEY,
          employeeId TEXT NOT NULL,
          periodStart TEXT NOT NULL,   -- ISO8601
          periodEnd   TEXT NOT NULL,   -- ISO8601
          baseSalary  REAL,
          allowances  REAL,
          deductions  REAL,
          advances    REAL,
          totalPaid   REAL,
          method      TEXT,
          paymentDate TEXT,            -- ISO8601
          note        TEXT
        )
      ''');

      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salary_pay_emp ON $_table(employeeId);');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salary_pay_date ON $_table(paymentDate);');
    } catch (e) {
      print('Error ensuring table creation: $e');
      rethrow; // Re-throw to handle at a higher level
    }
  }

  // ================= Helpers =================
  static bool _isBank(String? m) {
    final s = (m ?? '').toLowerCase();
    return s.contains('bank') || s.contains('transfer') || s.contains('visa');
  }

  static double _nz(num? v) => (v ?? 0).toDouble();

  static Future<bool> _glExists(String source, String sourceId) async {
    final db = await _db;
    final r = await db.query('gl_entries',
        columns: ['id'],
        where: 'source=? AND source_id=?',
        whereArgs: [source, sourceId],
        limit: 1);
    return r.isNotEmpty;
  }

  static Future<int> _idByCodeOrEnsure({
    required String code,
    required String name,
    required String type,
    required String normal,
  }) async {
    final existing = await DBService.getAccountIdByCode(code);
    if (existing != null) return existing;
    return DBService.ensureAccount(
      code: code,
      name: name,
      type: type,
      normalBalance: normal,
    );
  }

  static Future<void> _postGL(SalaryPayment p) async {
    if (await _glExists('PAYROLL', p.id)) return;

    final totalGross =
        _nz(p.baseSalary) + _nz(p.allowances) - _nz(p.deductions);
    final adv = _nz(p.advances);
    final paid = _nz(p.totalPaid);

    final cashOrBankId = await _idByCodeOrEnsure(
      code: _isBank(p.method) ? GL.bank : GL.cash,
      name: _isBank(p.method) ? 'البنك' : 'الصندوق',
      type: 'ASSET',
      normal: 'DEBIT',
    );

    final salariesExpenseId = await _idByCodeOrEnsure(
      code: GL.salariesExpense,
      name: 'مصروف رواتب',
      type: 'EXPENSE',
      normal: 'DEBIT',
    );

    final empAdvId = await _idByCodeOrEnsure(
      code: '${GL.empAdvances}.E${p.employeeId}',
      name: 'سلف موظف - ${p.employeeId}',
      type: 'ASSET',
      normal: 'DEBIT',
    );

    try {
      await GL.post(
        date: p.paymentDate,
        ref: '${p.periodStart}→${p.periodEnd}',
        source: 'PAYROLL',
        sourceId: p.id,
        note: p.note ?? 'دفع راتب',
        lines: [
          {'account_id': salariesExpenseId, 'debit': totalGross, 'credit': 0.0},
          if (adv > 0)
            {
              'account_id': empAdvId,
              'debit': 0.0,
              'credit': adv,
              'party_type': 'EMPLOYEE',
              'party_id': p.employeeId,
            },
          if (paid > 0)
            {'account_id': cashOrBankId, 'debit': 0.0, 'credit': paid},
        ],
      );
    } catch (e) {
      print('Error posting GL entry: $e');
      rethrow; // Handle failure in GL posting
    }
  }

  static Future<void> _reverseGL(String id) async {
    final db = await _db;
    final head = await db.query('gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['PAYROLL', id],
        limit: 1);
    if (head.isNotEmpty) {
      final entryId = head.first['id'] as int;
      await DBService.reverseEntryGL(entryId,
          note: 'Reverse payroll by delete/update');
    }
  }

  // ================= CRUD + GL =================

  static Future<void> insert(SalaryPayment payment) async {
    await ensureTable();
    final db = await _db;
    await db.insert(
      _table,
      payment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _postGL(payment);
  }

  static Future<void> update(SalaryPayment payment) async {
    await ensureTable();
    final db = await _db;
    await _reverseGL(payment.id);
    await db.update(
      _table,
      payment.toMap(),
      where: 'id = ?',
      whereArgs: [payment.id],
    );
    await _postGL(payment);
  }

  static Future<void> delete(String id) async {
    await ensureTable();
    final db = await _db;
    await _reverseGL(id);
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<SalaryPayment>> getByEmployee(String employeeId) async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'employeeId = ?',
      whereArgs: [employeeId],
      orderBy: 'paymentDate DESC, id DESC',
    );
    return rows.map(SalaryPayment.fromMap).toList();
  }

  static Future<List<SalaryPayment>> getByDateRange(
      DateTime from, DateTime to) async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'paymentDate BETWEEN ? AND ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'paymentDate DESC, id DESC',
    );
    return rows.map(SalaryPayment.fromMap).toList();
  }

  static Future<List<SalaryPayment>> getAll() async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query(_table, orderBy: 'paymentDate DESC, id DESC');
    return rows.map(SalaryPayment.fromMap).toList();
  }
}
