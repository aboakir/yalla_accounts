// 📁 lib/features/employees/services/salary_database_service.dart
//
// SalaryDatabaseService — قسائم رواتب شهرية + ربط GL (v30)
// قفل الفترات عبر PayrollPeriodsService.
//
// GL:
//   • إثبات شهر:   Dr 5100 مصروف رواتب / Cr 2140.E<emp>
//   • صرف راتب:    Dr 2140.E<emp>        / Cr 1000|1010
//
// Sources:
//   PAYROLL_ACCRUAL  → source_id = "<employeeId>@<YYYY-MM>"
//   PAYROLL_PAYMENT  → source_id = "<employeeId>@<YYYY-MM>@<epochMicros>"
//
// ملاحظة: لا نشر تلقائي. استدعِ postMonthlyAccrual / paySalary عند الحاجة.

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

    if (hit.isNotEmpty) {
      final accrualId = int.tryParse('${hit.first['gl_accrual_id'] ?? ''}');
      final paymentId = int.tryParse('${hit.first['gl_payment_id'] ?? ''}');
      if (accrualId != null) {
        try {
          await DBService.reverseEntryGL(accrualId,
              note: 'Reverse salary accrual');
        } catch (_) {}
      }
      if (paymentId != null) {
        try {
          await DBService.reverseEntryGL(paymentId,
              note: 'Reverse salary payment');
        } catch (_) {}
      }
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

  // ───────────── GL: Accrual ─────────────
  static Future<void> postMonthlyAccrual({
    required String employeeId,
    required String employeeName,
    required String month, // YYYY-MM
    required double amount,
    DateTime? date,
  }) async {
    await ensureTable();
    _assertMonthFormat(month);

    final ps = _periodStart(month);
    final pe = _periodEnd(month);
    await PayrollPeriodsService.assertAccrualAllowed(
      employeeId: employeeId,
      periodStart: ps,
      periodEnd: pe,
    );

    final db = await DBService.database;

    final exist = await db.query(
      _table,
      columns: ['gl_accrual_id'],
      where: 'employeeId = ? AND month = ? AND gl_accrual_id IS NOT NULL',
      whereArgs: [employeeId, month],
      limit: 1,
    );
    if (exist.isNotEmpty) {
      throw StateError('تم إثبات راتب $employeeId لشهر $month مسبقًا.');
    }

    await _ensureSnapshotRowIfMissing(
      employeeId: employeeId,
      month: month,
      employeeName: employeeName,
    );

    final d = date ?? _periodEnd(month);
    final accExpense = await _accSalariesExpense(); // 5100
    final accPayable = await _accPayrollPayableSub(employeeId); // 2140.E<emp>

    int glId;
    try {
      glId = await DBService.postEntryGL(
        date: d,
        source: 'PAYROLL_ACCRUAL',
        sourceId: '$employeeId@$month',
        note: 'إثبات راتب $employeeName لشهر $month',
        lines: [
          {
            'account_id': accExpense,
            'debit': _r(amount),
            'credit': 0.0,
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
          },
          {
            'account_id': accPayable,
            'debit': 0.0,
            'credit': _r(amount),
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
          },
        ],
      );
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
      final existing = await DBService.getGlEntryIdBySource(
          'PAYROLL_ACCRUAL', '$employeeId@$month');
      if (existing == null) rethrow;
      glId = existing;
    }

    await db.update(
      _table,
      {
        'gl_accrual_id': glId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
    );

    await PayrollPeriodsService.ensurePeriodRow(ps.year, ps.month);
  }

  // ───────────── GL: Payment ─────────────
  // محدث: إدراج صف في payments بعد نشر GL ليتحدث سجل الدفعات ولوحة المالية.
  static Future<void> paySalary({
    required String employeeId,
    required String employeeName,
    required String month, // YYYY-MM
    required double amount,
    String method = 'cash',
    DateTime? date,
  }) async {
    await ensureTable();
    _assertMonthFormat(month);
    if (await _isLocked(month)) {
      throw StateError('فترة $month مقفلة. افتحها قبل الدفع.');
    }

    await _ensureSnapshotRowIfMissing(
      employeeId: employeeId,
      month: month,
      employeeName: employeeName,
    );

    final db = await DBService.database;
    final d = date ?? DateTime.now();
    final normalizedMethod = _normalizeMethod(method);

    final accPayable = await _accPayrollPayableSub(employeeId); // 2140.E<emp>
    final accCashBank = await _accCashOrBank(normalizedMethod); // 1000/1010

    int glId;
    final sourceId = '$employeeId@$month@${d.microsecondsSinceEpoch}';
    try {
      glId = await DBService.postEntryGL(
        date: d,
        source: 'PAYROLL_PAYMENT',
        sourceId: sourceId,
        note: 'صرف راتب $employeeName لشهر $month',
        lines: [
          {
            'account_id': accPayable,
            'debit': _r(amount),
            'credit': 0.0,
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
          },
          {
            'account_id': accCashBank,
            'debit': 0.0,
            'credit': _r(amount),
          },
        ],
      );
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
      final existing =
          await DBService.getGlEntryIdBySource('PAYROLL_PAYMENT', sourceId);
      if (existing == null) rethrow;
      glId = existing;
    }

    // ◼️ سجل دفعات مرآتي ليستفيد "سجل الدفعات" ولوحة المالية الحالية
    try {
      final payId = DBService.newUuid();
      await db.insert('payments', {
        'id': payId,
        'party_id': employeeId,
        'client_id': null,
        'repair_id': null,
        'invoice_id': null,
        'amount': _r(amount),
        'date': d.toIso8601String(),
        'method': normalizedMethod ?? 'cash',
        'accountName': _accountNameForMethod(normalizedMethod),
        'status': 'posted',
        'notes': 'صرف راتب $employeeName لشهر $month',
        'attachments': null,
        'relatedRepairId': null,
        'gl_entry_id': glId,
      });
    } catch (_) {
      // لا تفشل العملية لو تعذّر إدراج payments
    }

    // تحديث snapshot
    final row = await db.query(
      _table,
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
      limit: 1,
    );
    if (row.isNotEmpty) {
      final paid0 = _d(row.first['paid']);
      final due0 = _d(row.first['due']);
      final newPaid = _r(paid0 + amount);
      final newDue = _r(due0 - amount);

      await db.update(
        _table,
        {
          'paid': newPaid,
          'due': newDue < 0 ? 0.0 : newDue,
          'gl_payment_id': glId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'employeeId = ? AND month = ?',
        whereArgs: [employeeId, month],
      );
    }
  }

  // ───────────── GL: Reverse ─────────────
  static Future<void> reverseAccrual({
    required String employeeId,
    required String month,
  }) async {
    await ensureTable();
    _assertMonthFormat(month);
    if (await _isLocked(month)) {
      throw StateError('فترة $month مقفلة. افتحها قبل العكس.');
    }

    final db = await DBService.database;

    final row = await db.query(
      _table,
      columns: ['gl_accrual_id'],
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
      limit: 1,
    );

    final id = row.isNotEmpty
        ? int.tryParse('${row.first['gl_accrual_id'] ?? ''}')
        : null;
    if (id == null) return;

    try {
      await DBService.reverseEntryGL(id, note: 'Reverse salary accrual');
    } catch (_) {}

    await db.update(
      _table,
      {'gl_accrual_id': null, 'updated_at': DateTime.now().toIso8601String()},
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
    );
  }

  static Future<void> reversePayment({
    required String employeeId,
    required String month,
  }) async {
    await ensureTable();
    _assertMonthFormat(month);
    if (await _isLocked(month)) {
      throw StateError('فترة $month مقفلة. افتحها قبل العكس.');
    }

    final db = await DBService.database;

    final row = await db.query(
      _table,
      columns: ['gl_payment_id'],
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
      limit: 1,
    );

    final id = row.isNotEmpty
        ? int.tryParse('${row.first['gl_payment_id'] ?? ''}')
        : null;
    if (id == null) return;

    try {
      await DBService.reverseEntryGL(id, note: 'Reverse salary payment');
    } catch (_) {}

    await db.update(
      _table,
      {'gl_payment_id': null, 'updated_at': DateTime.now().toIso8601String()},
      where: 'employeeId = ? AND month = ?',
      whereArgs: [employeeId, month],
    );
  }
}
