import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';

// ربط بإعدادات الورشة
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

/// حالات حضور قياسية (مع دعم مرادفات عربية/إنجليزية عند القراءة)
class AttendanceStatus {
  static const present = 'حاضر';
  static const absent = 'غائب';
  static const paidLeave = 'إجازة_مدفوعة';
  static const unpaidLeave = 'إجازة_غير_مدفوعة';
  static const holiday = 'عطلة_رسمية';

  /// تطبيع أي قيمة حالة إلى مجموعة موحّدة
  /// Supports: underscore `_` or space, Arabic/English.
  static String normalize(String raw) {
    final s = raw.trim().toLowerCase();

    // حضور
    if (s == 'حاضر' || s == 'حضور' || s == 'present') return present;

    // غياب
    if (s == 'غائب' || s == 'غياب' || s == 'absent') return absent;

    // إجازة مدفوعة
    if (s == 'إجازة مدفوعة' ||
        s == 'اجازة مدفوعة' ||
        s == 'إجازة_مدفوعة' ||
        s == 'اجازة_مدفوعة' ||
        s == 'paid leave' ||
        s == 'paid_leave') {
      return paidLeave;
    }

    // إجازة غير مدفوعة
    if (s == 'إجازة غير مدفوعة' ||
        s == 'اجازة غير مدفوعة' ||
        s == 'إجازة_غير_مدفوعة' ||
        s == 'اجازة_غير_مدفوعة' ||
        s == 'unpaid leave' ||
        s == 'unpaid_leave') {
      return unpaidLeave;
    }

    // عطلة رسمية
    if (s == 'عطلة رسمية' ||
        s == 'عطلة_رسمية' ||
        s == 'official holiday' ||
        s == 'holiday') {
      return holiday;
    }

    // "إجازة" عامة بدون تحديد → اعتبرها مدفوعة افتراضيًا
    if (s == 'إجازة' || s == 'اجازة' || s == 'leave') return paidLeave;

    // افتراضي: غياب
    return absent;
  }
}

/// سياسة احتساب الحضور/الراتب مبنية على إعدادات الورشة
class AttendancePolicy {
  /// ساعات الدوام القياسية لليوم (paid regular hours per day)
  final double hoursPerDay;

  /// بداية الشفت بصيغة HH:mm
  final String shiftStart;

  /// نهاية الشفت بصيغة HH:mm
  final String shiftEnd;

  /// دقائق الاستراحة ضمن اليوم تُخصم من الساعات الفعلية
  final int breakMinutes;

  /// تُدفع العطل الرسمية؟
  final bool payOfficialHolidays;

  /// تُدفع الإجازات القانونية؟
  final bool payLegalLeave;

  /// daily | weekly | monthly (للتوسّع لاحقًا)
  final String payProgram;

  /// معامل ساعات الإضافي
  final double overtimeMultiplier;

  /// اختيارية: "1,2,3,4,5,6" (أحد..جمعة) لتحديد أيام العمل
  final String? weekWorkdays;

  const AttendancePolicy({
    required this.hoursPerDay,
    this.shiftStart = '09:00',
    this.shiftEnd = '17:00',
    this.breakMinutes = 0,
    this.payOfficialHolidays = true,
    this.payLegalLeave = true,
    this.payProgram = 'monthly',
    this.overtimeMultiplier = 1.25,
    this.weekWorkdays,
  });

  /// مصنع Policy من إعدادات الورشة المخزّنة
  static Future<AttendancePolicy> fromWorkshopSettings() async {
    final s = await WorkshopSettingsService.instance.getOrDefaults();
    return AttendancePolicy(
      hoursPerDay: (s.dailyHours ?? 8).toDouble(),
      shiftStart: s.workStart ?? '09:00',
      shiftEnd: s.workEnd ?? '17:00',
      breakMinutes: s.breakMinutes ?? 0,
      weekWorkdays: s.weekWorkdays,
    );
  }
}

/// نتيجة تلخيص الحضور لفترة
class AttendanceSummary {
  final String employeeId;
  final DateTime from;
  final DateTime to;

  final int presentDays;
  final int paidLeaveDays;
  final int unpaidLeaveDays;
  final int holidayDays;
  final int absentDays;

  final double workedHours; // مجموع ساعات العمل الفعلية لأيام الحضور
  final double payableRegularHours; // ساعات تُحسب كدوام أساسي بعد خصم الاستراحة
  final double overtimeHours; // ساعات إضافية فوق ساعات اليوم القياسية
  final int lateMinutes; // مجموع دقائق التأخير
  final int earlyExitMinutes; // مجموع دقائق الخروج المبكر
  final int scheduledWorkDays; // أيام العمل المجدولة من إعدادات الورشة
  final int missingWorkDays; // أيام عمل بلا سجل حضور وتُعامل كغياب

  /// أيام مدفوعة فعليًا ≈ payableRegularHours / hoursPerDay
  final double payableDays;

  const AttendanceSummary({
    required this.employeeId,
    required this.from,
    required this.to,
    required this.presentDays,
    required this.paidLeaveDays,
    required this.unpaidLeaveDays,
    required this.holidayDays,
    required this.absentDays,
    required this.workedHours,
    required this.payableRegularHours,
    required this.overtimeHours,
    required this.lateMinutes,
    required this.earlyExitMinutes,
    required this.scheduledWorkDays,
    required this.missingWorkDays,
    required this.payableDays,
  });

  Map<String, Object?> toMap() => {
        'employeeId': employeeId,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'presentDays': presentDays,
        'paidLeaveDays': paidLeaveDays,
        'unpaidLeaveDays': unpaidLeaveDays,
        'holidayDays': holidayDays,
        'absentDays': absentDays,
        'workedHours': AttendanceDatabaseService._round2(workedHours),
        'payableRegularHours':
            AttendanceDatabaseService._round2(payableRegularHours),
        'overtimeHours': AttendanceDatabaseService._round2(overtimeHours),
        'lateMinutes': lateMinutes,
        'earlyExitMinutes': earlyExitMinutes,
        'scheduledWorkDays': scheduledWorkDays,
        'missingWorkDays': missingWorkDays,
        'payableDays': AttendanceDatabaseService._round2(payableDays),
      };
}

class AttendanceDatabaseService {
  static const String _table = 'attendance';

  static Future<Database> get _db async => DBService.database;

  /// إنشاء/تأكيد الجدول والفهارس
  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        employeeId TEXT NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        checkIn TEXT,     -- HH:mm اختياري
        checkOut TEXT,    -- HH:mm اختياري
        hoursWorked REAL, -- إن لم تُحدَّد تُحسب من HH:mm
        notes TEXT,
        FOREIGN KEY(employeeId) REFERENCES employees(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attendance_emp_date ON $_table(employeeId, date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attendance_date ON $_table(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attendance_status ON $_table(status)');
  }

  /// تستدعى من DBService.onCreate
  static Future<void> createTable(Database db) async => _ensureSchema(db);

  // ───────────── CRUD ─────────────

  static Future<void> insertAttendance(Attendance record) async {
    final db = await _db;
    await _ensureSchema(db);
    await db.transaction((txn) async {
      await txn.insert(
        _table,
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await AuditTrailService.log(
        executor: txn,
        action: 'ATTENDANCE_CREATED',
        entityType: 'attendance',
        entityId: record.id,
        after: record.toMap(),
      );
    });
  }

  static Future<void> updateAttendance(
    Attendance record, {
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('Attendance edit reason is required.');
    }
    final db = await _db;
    await _ensureSchema(db);
    await db.transaction((txn) async {
      final beforeRows = await txn.query(
        _table,
        where: 'id = ?',
        whereArgs: [record.id],
        limit: 1,
      );
      if (beforeRows.isEmpty) {
        throw StateError('Attendance record not found: ${record.id}');
      }
      final before = Map<String, Object?>.from(beforeRows.first);
      await txn.update(
        _table,
        record.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
      await AuditTrailService.log(
        executor: txn,
        action: 'ATTENDANCE_UPDATED',
        entityType: 'attendance',
        entityId: record.id,
        before: before,
        after: record.toMap(),
        reason: trimmedReason,
      );
    });
  }

  static Future<void> deleteAttendance(
    String id, {
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('Attendance delete reason is required.');
    }
    final db = await _db;
    await _ensureSchema(db);
    await db.transaction((txn) async {
      final beforeRows = await txn.query(
        _table,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (beforeRows.isEmpty) return;
      final before = Map<String, Object?>.from(beforeRows.first);
      await AuditTrailService.log(
        executor: txn,
        action: 'ATTENDANCE_DELETED',
        entityType: 'attendance',
        entityId: id,
        before: before,
        reason: trimmedReason,
      );
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<List<Attendance>> getAllAttendance() async {
    final db = await _db;
    await _ensureSchema(db);
    final maps = await db.query(_table, orderBy: 'date DESC, id DESC');
    return maps.map((e) => Attendance.fromMap(e)).toList();
  }

  static Future<List<Attendance>> getAttendanceForEmployee({
    required String employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _db;
    await _ensureSchema(db);
    final maps = await db.query(
      _table,
      where: 'employeeId = ? AND date BETWEEN ? AND ?',
      whereArgs: [employeeId, from.toIso8601String(), to.toIso8601String()],
      orderBy: 'date ASC, id ASC',
    );
    return maps.map((e) => Attendance.fromMap(e)).toList();
  }

  /// عدد أيام الغياب غير المدفوعة ضمن فترة
  static Future<int> getUnpaidAbsences({
    required String employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _db;
    await _ensureSchema(db);
    final maps = await db.query(
      _table,
      where: 'employeeId = ? AND date BETWEEN ? AND ? AND status = ?',
      whereArgs: [
        employeeId,
        from.toIso8601String(),
        to.toIso8601String(),
        AttendanceStatus.absent
      ],
    );
    return maps.length;
  }

  /// إدخال/تحديث دفعي
  static Future<void> upsertBulk(List<Attendance> records) async {
    if (records.isEmpty) return;
    final db = await _db;
    await _ensureSchema(db);
    final batch = db.batch();
    for (final r in records) {
      batch.insert(_table, r.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ───────────── أدوات وقت/أرقام ─────────────

  static double _round2(num x) => double.parse(x.toStringAsFixed(2));

  /// يحوّل 'HH:mm' إلى دقائق منذ منتصف الليل
  static int? _parseHmmToMin(String? hhmm) {
    if (hhmm == null || hhmm.trim().isEmpty) return null;
    final parts = hhmm.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  static DateTime _at(DateTime d, String hhmm) {
    final m = _parseHmmToMin(hhmm) ?? 0;
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  /// يحسب ساعات العمل الفعلية من checkIn/checkOut مع دعم وردية تتجاوز منتصف الليل
  static double _workedHoursFrom(Attendance r) {
    // يفضّل hoursWorked إن كانت موجودة
    if ((r.hoursWorked ?? 0) > 0) return _round2(r.hoursWorked!);

    final inMin = _parseHmmToMin(r.checkIn);
    var outMin = _parseHmmToMin(r.checkOut);
    if (inMin == null || outMin == null) return 0.0;

    // إذا الخروج قبل الدخول → نفترض وردية ليلية (اليوم التالي)
    if (outMin < inMin) outMin += 24 * 60;

    final diffMin = outMin - inMin;
    if (diffMin <= 0) return 0.0;
    return _round2(diffMin / 60.0);
  }

  static int _lateMinutesFrom(String? checkIn, DateTime shiftStart) {
    final inMin = _parseHmmToMin(checkIn);
    if (inMin == null) return 0;
    final baseMin = shiftStart.hour * 60 + shiftStart.minute;
    final d = inMin - baseMin;
    return d > 0 ? d : 0;
  }

  static int _earlyExitMinutesFrom(String? checkOut, DateTime shiftEnd) {
    final outMin = _parseHmmToMin(checkOut);
    if (outMin == null) return 0;
    final baseMin = shiftEnd.hour * 60 + shiftEnd.minute;
    final d = baseMin - outMin;
    return d > 0 ? d : 0;
  }

  static Set<int> _configuredWeekdays(AttendancePolicy policy) {
    final raw = (policy.weekWorkdays ?? '').trim();
    if (raw.isEmpty) return const {1, 2, 3, 4, 5, 6};
    final days = raw
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .where((e) => e >= DateTime.monday && e <= DateTime.sunday)
        .toSet();
    return days.isEmpty ? const {1, 2, 3, 4, 5, 6} : days;
  }

  static int _scheduledWorkDays(
    DateTime from,
    DateTime to,
    AttendancePolicy policy,
  ) {
    final weekdays = _configuredWeekdays(policy);
    var cursor = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    var count = 0;
    while (!cursor.isAfter(end)) {
      if (weekdays.contains(cursor.weekday)) count += 1;
      cursor = cursor.add(const Duration(days: 1));
    }
    return count;
  }

  // ───────────── تلخيص لاستخدام الرواتب ─────────────

  /// نسخة مريحة: تبني السياسة تلقائيًا من إعدادات الورشة
  static Future<AttendanceSummary> summarizeForPayrollUsingWorkshopSettings({
    required String employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final policy = await AttendancePolicy.fromWorkshopSettings();
    return summarizeForPayroll(
      employeeId: employeeId,
      from: from,
      to: to,
      policy: policy,
    );
  }

  /// التلخيص الفعلي لفترة حسب السياسة المعطاة
  static Future<AttendanceSummary> summarizeForPayroll({
    required String employeeId,
    required DateTime from,
    required DateTime to,
    required AttendancePolicy policy,
  }) async {
    final rows = await getAttendanceForEmployee(
      employeeId: employeeId,
      from: from,
      to: to,
    );

    int presentDays = 0;
    int paidLeaveDays = 0;
    int unpaidLeaveDays = 0;
    int holidayDays = 0;
    int absentDays = 0;

    double workedHours = 0.0;
    double payableRegularHours = 0.0;
    double overtimeHours = 0.0;
    int lateMinutes = 0;
    int earlyExitMinutes = 0;

    for (final r in rows) {
      final d0 = DateTime(r.date.year, r.date.month, r.date.day);

      // بناء وقت بداية ونهاية الشفت مع دعم عبور منتصف الليل
      final shiftStartDT = _at(d0, policy.shiftStart);
      var shiftEndDT = _at(d0, policy.shiftEnd);
      if (!shiftEndDT.isAfter(shiftStartDT)) {
        // نهاية الشفت في اليوم التالي
        shiftEndDT = shiftEndDT.add(const Duration(days: 1));
      }

      final st = AttendanceStatus.normalize(r.status);

      if (st == AttendanceStatus.present) {
        presentDays += 1;

        // ساعات فعلية
        final wh = _workedHoursFrom(r);
        workedHours += wh;

        // خصم الاستراحة من الساعات المدفوعة فقط
        final whAfterBreak =
            math.max(0.0, wh - (policy.breakMinutes.toDouble() / 60.0));

        // تأخير
        lateMinutes += _lateMinutesFrom(r.checkIn, shiftStartDT);
        earlyExitMinutes += _earlyExitMinutesFrom(r.checkOut, shiftEndDT);

        // احتساب الساعات المنتظمة مقابل الإضافي
        final base = policy.hoursPerDay;
        if (whAfterBreak > base) {
          payableRegularHours += base;
          overtimeHours += _round2(whAfterBreak - base);
        } else {
          payableRegularHours += whAfterBreak;
        }
      } else if (st == AttendanceStatus.paidLeave) {
        paidLeaveDays += 1;
        if (policy.payLegalLeave) {
          payableRegularHours += policy.hoursPerDay;
        }
      } else if (st == AttendanceStatus.unpaidLeave) {
        unpaidLeaveDays += 1;
      } else if (st == AttendanceStatus.holiday) {
        holidayDays += 1;
        if (policy.payOfficialHolidays) {
          payableRegularHours += policy.hoursPerDay;
        }
      } else if (st == AttendanceStatus.absent) {
        absentDays += 1;
      }
    }

    final scheduledWorkDays = _scheduledWorkDays(from, to, policy);
    final coveredScheduledDates = rows
        .map((r) => DateTime(r.date.year, r.date.month, r.date.day))
        .where((d) => _configuredWeekdays(policy).contains(d.weekday))
        .map((d) => '${d.year}-${d.month}-${d.day}')
        .toSet()
        .length;
    final missingWorkDays =
        math.max(0, scheduledWorkDays - coveredScheduledDates);
    absentDays += missingWorkDays;

    final payableDays = policy.hoursPerDay > 0
        ? _round2(payableRegularHours / policy.hoursPerDay)
        : 0.0;

    return AttendanceSummary(
      employeeId: employeeId,
      from: from,
      to: to,
      presentDays: presentDays,
      paidLeaveDays: paidLeaveDays,
      unpaidLeaveDays: unpaidLeaveDays,
      holidayDays: holidayDays,
      absentDays: absentDays,
      workedHours: workedHours,
      payableRegularHours: payableRegularHours,
      overtimeHours: overtimeHours,
      lateMinutes: lateMinutes,
      earlyExitMinutes: earlyExitMinutes,
      scheduledWorkDays: scheduledWorkDays,
      missingWorkDays: missingWorkDays,
      payableDays: payableDays,
    );
  }

  // ───────────── مساعدات عددية للرواتب ─────────────

  /// خصم التأخير = دقائق التأخير × أجر الدقيقة
  static double computeLateDeduction({
    required int lateMinutes,
    required double hourlyRate,
  }) {
    final hours = lateMinutes / 60.0;
    return _round2(hours * hourlyRate);
  }

  /// بدل الإضافي = ساعات إضافية × أجر ساعة × معامل إضافي
  static double computeOvertimeAddition({
    required double overtimeHours,
    required double hourlyRate,
    double overtimeMultiplier = 1.25,
  }) {
    return _round2(overtimeHours * hourlyRate * overtimeMultiplier);
  }
}
