// 📁 lib/features/employees/services/payroll_periods_service.dart
//
// PayrollPeriodsService — إدارة/قفل فترات الرواتب الشهرية + منع التكرار.
// Table: salary_periods(month TEXT PRIMARY KEY, is_locked INTEGER, locked_at TEXT, note TEXT)
//
// API الأساسية:
//   ensureTable()
//   ensurePeriodRow(year, month)
//   getStatus(year, month) / getStatusYm(yyyyMm) → 'OPEN' | 'LOCKED' | null
//   isLocked(year, month) / isLockedYm(yyyyMm) → bool
//   lockPeriod(year, month, {note}) / lockMonth(yyyyMm, {note})
//   unlockPeriod(year, month) / unlockMonth(yyyyMm)
//   ensureOpen(year, month) / ensureOpenYm(yyyyMm)
//   existsRunForMonth(employeeId, year, month) → bool
//   assertAccrualAllowed(employeeId, periodStart, periodEnd)
//   listPeriods({limit})
//
// ملاحظات:
// - يعتمد فحص التكرار على payroll_runs.period_start (ISO8601 TEXT).
// - لا تغييرات مكسّرة؛ الدوال القديمة بقيت كما هي وأضيفت overloads للراحة.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';

class PayrollPeriodsService {
  PayrollPeriodsService._();

  static const String _table = 'salary_periods';

  // ===== Schema =====
  static Future<void> ensureTable() async {
    final db = await DBService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table(
        month      TEXT PRIMARY KEY,           -- YYYY-MM
        is_locked  INTEGER NOT NULL DEFAULT 0, -- 0=OPEN, 1=LOCKED
        locked_at  TEXT,
        note       TEXT
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_salary_periods_locked ON $_table(is_locked);',
    );
  }

  static Future<void> ensurePeriodRow(int year, int month) async {
    await ensureTable();
    final db = await DBService.database;
    final key = _ym(year, month);

    final rows = await db.query(
      _table,
      columns: ['month'],
      where: 'month=?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert(
        _table,
        {
          'month': key,
          'is_locked': 0,
          'locked_at': null,
          'note': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // ===== Status / Locking =====

  static Future<String?> getStatus(int year, int month) async {
    await ensureTable();
    final db = await DBService.database;
    final key = _ym(year, month);
    final rows = await db.query(
      _table,
      columns: ['is_locked'],
      where: 'month=?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final locked = (rows.first['is_locked'] as int? ?? 0) == 1;
    return locked ? 'LOCKED' : 'OPEN';
  }

  /// Overload: yyyy-MM
  static Future<String?> getStatusYm(String yyyyMm) async {
    final y = _parseYear(yyyyMm);
    final m = _parseMonth(yyyyMm);
    return getStatus(y, m);
  }

  static Future<bool> isLocked(int year, int month) async {
    return (await getStatus(year, month)) == 'LOCKED';
  }

  /// Overload: yyyy-MM
  static Future<bool> isLockedYm(String yyyyMm) async {
    final y = _parseYear(yyyyMm);
    final m = _parseMonth(yyyyMm);
    return isLocked(y, m);
  }

  static Future<void> lockPeriod(int year, int month, {String? note}) async {
    await AuthorizationGuard.require(PermissionKeys.payrollManage);
    await ensurePeriodRow(year, month);
    final db = await DBService.database;
    final key = _ym(year, month);
    await db.update(
      _table,
      {
        'is_locked': 1,
        'locked_at': DateTime.now().toIso8601String(),
        'note': note,
      },
      where: 'month=?',
      whereArgs: [key],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static Future<void> unlockPeriod(int year, int month) async {
    await AuthorizationGuard.require(PermissionKeys.payrollManage);
    await ensurePeriodRow(year, month);
    final db = await DBService.database;
    final key = _ym(year, month);
    await db.update(
      _table,
      {'is_locked': 0, 'locked_at': null, 'note': null},
      where: 'month=?',
      whereArgs: [key],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ==== Aliases ====

  static Future<void> lockMonth(String yyyyMm, {String? note}) async {
    final y = _parseYear(yyyyMm);
    final m = _parseMonth(yyyyMm);
    await lockPeriod(y, m, note: note);
  }

  static Future<void> unlockMonth(String yyyyMm) async {
    final y = _parseYear(yyyyMm);
    final m = _parseMonth(yyyyMm);
    await unlockPeriod(y, m);
  }

  /// يضمن أن الفترة موجودة ومفتوحة وإلا يرمي خطأ.
  static Future<void> ensureOpen(int year, int month) async {
    await ensurePeriodRow(year, month);
    if (await isLocked(year, month)) {
      throw StateError('فترة $year-$month مقفلة. افتح الفترة أولاً.');
    }
  }

  /// Overload: yyyy-MM
  static Future<void> ensureOpenYm(String yyyyMm) async {
    final y = _parseYear(yyyyMm);
    final m = _parseMonth(yyyyMm);
    await ensureOpen(y, m);
  }

  // ===== Duplicate Guard (per employee + month) =====

  /// هل يوجد استحقاق لنفس الموظف في نفس الشهر؟ يستثني الـ REVERSED.
  /// يعتمد على period_start ضمن payroll_runs (ISO8601 TEXT).
  static Future<bool> existsRunForMonth({
    required String employeeId,
    required int year,
    required int month,
  }) async {
    final db = await DBService.database;
    final ym = _ym(year, month);
    final rows = await db.rawQuery(
      '''
      SELECT 1
      FROM payroll_runs
      WHERE employee_id = ?
        AND strftime('%Y-%m', period_start) = ?
        AND (status IS NULL OR status != 'REVERSED')
      LIMIT 1;
      ''',
      [employeeId, ym],
    );
    return rows.isNotEmpty;
  }

  /// يمنع الاستحقاق إذا كانت الفترة مُقفلة أو موجود استحقاق لنفس الموظف في نفس الشهر.
  static Future<void> assertAccrualAllowed({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final y = periodStart.year;
    final m = periodStart.month;

    await ensurePeriodRow(y, m);
    if (await isLocked(y, m)) {
      throw StateError('لا يمكن الاستحقاق لشهر ${_ym(y, m)} لأنه مُقفَل.');
    }

    if (await existsRunForMonth(employeeId: employeeId, year: y, month: m)) {
      throw StateError(
          'موجود استحقاق مسبق للموظف $employeeId في ${_ym(y, m)}.');
    }

    if (!_isSameOrAfter(periodEnd, periodStart)) {
      throw ArgumentError(
          'period_end يجب أن يكون في نفس اليوم أو بعد period_start.');
    }
  }

  // ===== Queries =====

  static Future<List<Map<String, Object?>>> listPeriods({int? limit}) async {
    await AuthorizationGuard.require(PermissionKeys.payrollView);
    await ensureTable();
    final db = await DBService.database;
    return db.query(
      _table,
      orderBy: 'month DESC',
      limit: limit,
    );
  }

  // ===== Helpers =====

  static String _ym(int year, int month) {
    final mm = month < 10 ? '0$month' : '$month';
    return '$year-$mm';
  }

  static int _parseYear(String yyyyMm) {
    if (yyyyMm.length < 7 || yyyyMm[4] != '-') {
      throw ArgumentError('format must be yyyy-MM');
    }
    final y = int.tryParse(yyyyMm.substring(0, 4));
    if (y == null || y <= 0) throw ArgumentError('invalid year in yyyy-MM');
    return y;
  }

  static int _parseMonth(String yyyyMm) {
    if (yyyyMm.length < 7 || yyyyMm[4] != '-') {
      throw ArgumentError('format must be yyyy-MM');
    }
    final m = int.tryParse(yyyyMm.substring(5, 7));
    if (m == null || m < 1 || m > 12) {
      throw ArgumentError('invalid month in yyyy-MM');
    }
    return m;
  }

  static bool _isSameOrAfter(DateTime a, DateTime b) {
    if (_isSameDay(a, b)) return true;
    return a.isAfter(b); // a >= b
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
