import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';

class AttendanceReportDay {
  const AttendanceReportDay({
    required this.date,
    required this.status,
    required this.workedHours,
    required this.lateMinutes,
    this.record,
    this.inferredAbsence = false,
  });

  final DateTime date;
  final String status;
  final double workedHours;
  final int lateMinutes;
  final Attendance? record;
  final bool inferredAbsence;

  String? get checkIn => record?.checkIn;
  String? get checkOut => record?.checkOut;
  String? get notes => record?.notes;
}

class AttendancePeriodReport {
  const AttendancePeriodReport({
    required this.from,
    required this.to,
    required this.days,
    required this.presentDays,
    required this.absentDays,
    required this.totalWorkedHours,
    required this.totalLateMinutes,
  });

  final DateTime from;
  final DateTime to;
  final List<AttendanceReportDay> days;
  final int presentDays;
  final int absentDays;
  final double totalWorkedHours;
  final int totalLateMinutes;
}

abstract final class AttendanceReportingService {
  static AttendancePeriodReport build({
    required List<Attendance> records,
    required String employeeId,
    required DateTime from,
    required DateTime to,
    required AttendancePolicy policy,
    DateTime? asOf,
  }) {
    final start = _day(from);
    final end = _day(to);
    if (end.isBefore(start)) {
      throw ArgumentError('نهاية الفترة تسبق بدايتها.');
    }
    if (employeeId.trim().isEmpty) {
      return AttendancePeriodReport(
        from: start,
        to: end,
        days: const [],
        presentDays: 0,
        absentDays: 0,
        totalWorkedHours: 0,
        totalLateMinutes: 0,
      );
    }

    final cutoff = _day(asOf ?? DateTime.now());
    final workdays = _configuredWeekdays(policy);
    final byDate = <String, Attendance>{};
    for (final record in records) {
      if (record.employeeId != employeeId) continue;
      final day = _day(record.date);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      byDate[_key(day)] = record;
    }

    final days = <AttendanceReportDay>[];
    var presentDays = 0;
    var absentDays = 0;
    var totalWorkedHours = 0.0;
    var totalLateMinutes = 0;

    for (var day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))) {
      final record = byDate[_key(day)];
      final isScheduled = workdays.contains(day.weekday);

      if (record == null) {
        final inferred = isScheduled && !day.isAfter(cutoff);
        if (inferred) absentDays += 1;
        days.add(AttendanceReportDay(
          date: day,
          status: inferred ? AttendanceStatus.absent : 'غير مجدول',
          workedHours: 0,
          lateMinutes: 0,
          inferredAbsence: inferred,
        ));
        continue;
      }

      final normalized = AttendanceStatus.normalize(record.status);
      final worked =
          normalized == AttendanceStatus.present ? _workedHours(record) : 0.0;
      final late = normalized == AttendanceStatus.present
          ? _lateMinutes(record.checkIn, policy.shiftStart)
          : 0;

      if (normalized == AttendanceStatus.present) presentDays += 1;
      if (normalized == AttendanceStatus.absent) absentDays += 1;
      totalWorkedHours += worked;
      totalLateMinutes += late;

      days.add(AttendanceReportDay(
        date: day,
        status: normalized,
        workedHours: worked,
        lateMinutes: late,
        record: record,
      ));
    }

    return AttendancePeriodReport(
      from: start,
      to: end,
      days: List.unmodifiable(days),
      presentDays: presentDays,
      absentDays: absentDays,
      totalWorkedHours: _round2(totalWorkedHours),
      totalLateMinutes: totalLateMinutes,
    );
  }

  static Set<int> _configuredWeekdays(AttendancePolicy policy) {
    final raw = (policy.weekWorkdays ?? '').trim();
    if (raw.isEmpty) return const {1, 2, 3, 4, 5, 6};
    final parsed = raw
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .where((value) => value >= DateTime.monday && value <= DateTime.sunday)
        .toSet();
    return parsed.isEmpty ? const {1, 2, 3, 4, 5, 6} : parsed;
  }

  static double _workedHours(Attendance record) {
    final stored = record.hoursWorked;
    if (stored != null && stored.isFinite && stored >= 0) {
      return _round2(stored);
    }
    final start = _minutes(record.checkIn);
    var end = _minutes(record.checkOut);
    if (start == null || end == null) return 0;
    if (end < start) end += 24 * 60;
    return _round2((end - start) / 60);
  }

  static int _lateMinutes(String? checkIn, String shiftStart) {
    final actual = _minutes(checkIn);
    final scheduled = _minutes(shiftStart);
    if (actual == null || scheduled == null) return 0;
    return actual > scheduled ? actual - scheduled : 0;
  }

  static int? _minutes(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _key(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static double _round2(num value) => double.parse(value.toStringAsFixed(2));
}
