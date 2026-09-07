// 📁 lib/features/employees/services/salary_database_service.dart
//
// SalaryDatabaseService — legacy salary snapshot compatibility (financial writes disabled)
// قفل الفترات عبر PayrollPeriodsService.
//
// Stage 4: this table is a compatibility snapshot only.
// Financial accrual/payment commands are disabled; payroll_runs + vouchers are canonical.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/employees/models/salary.dart';
import 'package:yalla_accounts/features/employees/services/payroll_periods_service.dart';

class SalaryDatabaseService {
  static const String _table = 'salaries';

  // ───────────── Schema: snapshots فقط ─────────────
  static Future<void> ensureTable() async {
    final db = await DBService.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        employeeId     TEXT NOT NULL,
        month          TEXT NOT NULL,            -- YYYY-MM
        employeeName   TEXT,
        base           REAL NOT NULL DEFAULT 0,  -- إجمالي قبل خصومات/سلف (للتوافق)
        advance        REAL NOT NULL DEFAULT 0,  -- سلف/حسميات مطبّقة
        total          REAL NOT NULL DEFAULT 0,  -- إجمالي مستحق (قد يُستخدم لعرض قديم)
        paid           REAL NOT NULL DEFAULT 0,
        due            REAL NOT NULL DEFAULT 0,
        gl_accrual_id  INTEGER,
        gl_payment_id  INTEGER,
        created_at     TEXT,
        updated_at     TEXT,
        PRIMARY KEY (employeeId, month)
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_salaries_month ON $_table(month);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_salaries_emp   ON $_table(employeeId);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_salaries_glA   ON $_table(gl_accrual_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_salaries_glP   ON $_table(gl_payment_id);');
  }

  // ───────────── Helpers: Accounts ─────────────
  static Future<int> _accSalariesExpense() async {
    final id = await DBService.getAccountIdByCode('5100');
    if (id != null) return id;
    return DBService.ensureAccount(
      code: '5100',
      name: 'مصروف رواتب',
      type: 'EXPENSE',
      normalBalance: 'DEBIT',
    );
  }

  // 2140.E<employeeId> — مستحقات رواتب موظف فرعي
  static String _empSubCode(String root, String employeeId) =>
      '$root.E$employeeId';

  static Future<int> _accPayrollPayableSub(String employeeId) async {
    final code = _empSubCode('2140', employeeId);
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: 'مستحقات رواتب - $employeeId',
      type: 'LIABILITY',
      normalBalance: 'CREDIT',
    );
  }

  static bool _isBankMethod(String? m) {
    final s = (m ?? '').toLowerCase();
    return s.contains('bank') ||
        s.contains('transfer') ||
        s.contains('visa') ||
        s.contains('master') ||
        s.contains('card') ||
        s.contains('شيك') ||
        s.contains('cheque') ||
        s.contains('check') ||
        s.contains('تحويل');
  }

  static String? _normalizeMethod(String? m) {
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

  static String _accountNameForMethod(String? method) {
    final mm = _normalizeMethod(method);
    if (mm == 'bank' || mm == 'transfer' || mm == 'cheque') return 'البنك';
    return 'الصندوق';
  }

  static Future<int> _accCashOrBank(String? method) async {
    final bank = _isBankMethod(method);
    final code = bank ? '1010' : '1000';
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: bank ? 'البنك' : 'الصندوق',
      type: 'ASSET',
      normalBalance: 'DEBIT',
    );
  }

  static double _d(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double _r(double v) => double.parse(v.toStringAsFixed(2));

  static void _assertMonthFormat(String month) {
    final parts = month.split('-');
    if (parts.length != 2) {
      throw StateError('month غير صالح. الصيغة: YYYY-MM');
    }
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) {
      throw StateError('month غير صالح. الصيغة: YYYY-MM');
    }
  }

  static (int y, int m) _parseYm(String month) {
    _assertMonthFormat(month);
    final y = int.parse(month.substring(0, 4));
    final m = int.parse(month.substring(5, 7));
    return (y, m);
  }

  static DateTime _periodStart(String month) {
    final (y, m) = _parseYm(month);
    return DateTime(y, m, 1);
  }

  static DateTime _periodEnd(String month) {
    final (y, m) = _parseYm(month);
    return DateTime(y, m + 1, 0, 23, 59, 59);
  }

  // ───────────── Period lock via PayrollPeriodsService ─────────────
  static Future<bool> _isLocked(String month) async {
    final (y, m) = _parseYm(month);
    return PayrollPeriodsService.isLocked(y, m);
  }

  static Future<void> lockMonth(String month) async {
    final (y, m) = _parseYm(month);
    await PayrollPeriodsService.lockPeriod(y, m);
  }

  static Future<void> unlockMonth(String month) async {
    final (y, m) = _parseYm(month);
    await PayrollPeriodsService.unlockPeriod(y, m);
  }

  // ───────────── Internal: ensure snapshot row ─────────────
  static Future<void> _ensureSnapshotRowIfMissing({
    required String employeeId,
    required String month,
    String? employeeName,
  }) async {
    final db = await DBService.database;
    final hit = await db.query(
      _table,
      columns: ['employeeId'],
      where: 'employeeId=? AND month=?',
      whereArgs: [employeeId, month],
      limit: 1,
    );
    if (hit.isEmpty) {
      final nowIso = DateTime.now().toIso8601String();
      await db.insert(_table, {
        'employeeId': employeeId,
        'month': month,
        'employeeName': employeeName ?? '',
        'base': 0.0,
        'advance': 0.0,
        'total': 0.0,
        'paid': 0.0,
        'due': 0.0,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
    }
  }

  // ───────────── UPSERT/CRUD ─────────────
  static Future<void> upsertSalary(Salary s) async {
    await ensureTable();
    final db = await DBService.database;
    final nowIso = DateTime.now().toIso8601String();

    final base = s.gross;
    final adv = s.advancesApplied;
    final total = s.net;
    final paid = s.status == 'paid' ? s.net : 0.0;
    final due = s.status == 'paid' ? 0.0 : s.net;

    final map = <String, Object?>{
      'employeeId': s.employeeId,
      'month': s.month ?? '',
      'employeeName': s.employeeName ?? '',
      'base': _r(base),
      'advance': _r(adv),
      'total': _r(total),
      'paid': _r(paid),
      'due': _r(due),
      'updated_at': nowIso,
    };

    final old = await db.query(
      _table,
      columns: ['created_at'],
      where: 'employeeId=? AND month=?',
      whereArgs: [s.employeeId, s.month ?? ''],
      limit: 1,
    );
    map['created_at'] = old.isNotEmpty ? old.first['created_at'] : nowIso;

    await db.insert(_table, map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertSalary(Salary s) => upsertSalary(s);

  static Future<int> deleteSalary({
    required String employeeId,
    required String month,
  }) async {
    await ensureTable();
    final db = await DBService.database;
    final hit = await db.query(
      _table,
      columns: ['gl_accrual_id', 'gl_payment_id'],
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
      limit: 1,
    );
    if (hit.isNotEmpty &&
        (hit.first['gl_accrual_id'] != null ||
            hit.first['gl_payment_id'] != null)) {
      throw StateError(
        'Posted legacy salary snapshots cannot be deleted. Use formal payroll/voucher reversal.',
      );
    }
    return db.delete(
      _table,
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
    );
  }

  static Future<Salary?> getSalary({
    required String employeeId,
    required String month,
  }) async {
    await ensureTable();
    final db = await DBService.database;

    final rows = await db.query(
      _table,
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Salary.fromMap(rows.first);
  }

  static Future<List<Salary>> getSalaries() async {
    await ensureTable();
    final db = await DBService.database;

    final rows = await db.query(
      _table,
      orderBy: 'month DESC, employeeName COLLATE NOCASE ASC',
    );
    return rows.map(Salary.fromMap).toList();
  }

  static Future<List<Salary>> getSalariesByMonth(String month) async {
    await ensureTable();
    final db = await DBService.database;

    final rows = await db.query(
      _table,
      where: 'month = ?',
      whereArgs: [month],
      orderBy: 'employeeName COLLATE NOCASE ASC',
    );
    return rows.map(Salary.fromMap).toList();
  }

  // ───────────── Stage 4: legacy financial commands disabled ─────────────
  @Deprecated('Use PayrollEntitlementService.accrueFromAttendance')
  static Future<void> postMonthlyAccrual({
    required String employeeId,
    required String employeeName,
    required String month,
    required double amount,
    DateTime? date,
  }) async {
    throw StateError(
      'Legacy monthly salary accrual is disabled. Use attendance-driven payroll entitlement.',
    );
  }

  @Deprecated(
      'Use PayrollDatabaseService.pay to create a linked payment voucher')
  static Future<void> paySalary({
    required String employeeId,
    required String employeeName,
    required String month,
    required double amount,
    String method = 'cash',
    DateTime? date,
  }) async {
    throw StateError(
      'Legacy direct salary payment is disabled. Use a payment voucher linked to payroll entitlement.',
    );
  }

  @Deprecated('Use PayrollDatabaseService.reverseAccrual')
  static Future<void> reverseAccrual({
    required String employeeId,
    required String month,
  }) async {
    throw StateError(
      'Legacy salary accrual reversal is disabled. Reverse the payroll entitlement instead.',
    );
  }

  @Deprecated('Reverse the original payment voucher')
  static Future<void> reversePayment({
    required String employeeId,
    required String month,
  }) async {
    throw StateError(
      'Legacy salary payment reversal is disabled. Reverse the original payment voucher.',
    );
  }
}
