// 📁 lib/features/employees/providers/salary_provider.dart
//
// SalaryProvider — يحسب صافي الراتب الشهري من سجلات الحضور.
// الآن يقرأ إعدادات الدوام من WorkshopSettingsService:
// - workStart / workEnd (HH:mm) اختياريان
// - dailyHours لتحديد الساعات القياسية لليوم
// - breakMinutes لخصم الاستراحة من ساعات الحضور الفعلية
//
// المنطق المختصر:
// • حاضر: يحسب كسر يوم = min(max(ساعات العمل - الاستراحة, 0), ساعات اليوم) / ساعات اليوم
//   - ساعات العمل تُأخذ من hoursWorked إن وُجدت، وإلا تُحسب من checkIn/checkOut مع دعم وردية ليلية.
// • إجازة_مدفوعة: يوم كامل.
// • عطلة_رسمية: يوم كامل إذا payOfficialHolidays=true.
// • الصافي = baseSalary × (مجموع الأيام/الكسور المدفوعة ÷ totalWorkDaysInMonth).

import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart'
    show AttendanceStatus;

// 🔌 إعدادات الورشة
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

final salaryProvider = StateNotifierProvider<SalaryNotifier, double>((ref) {
  return SalaryNotifier();
});

class SalaryNotifier extends StateNotifier<double> {
  SalaryNotifier() : super(0.0);

  // cache: employeeId -> last result
  final Map<String, double> _byEmployee = {};

  /// API رئيسية
  Future<double> calculateAndReturn({
    required String employeeId,
    required double baseSalary,
    required int totalWorkDaysInMonth,
    required List<dynamic> attendanceRecords,
    bool payOfficialHolidays = false,
  }) async {
    // تحمّل الإعدادات أو افتراضات سليمة
    final ws = await WorkshopSettingsService.instance.getOrDefaults();

    // ساعات اليوم القياسية بالدقائق
    final dayStdMinutes = _safeMinutes(((ws.dailyHours ?? 8) * 60).toInt());
    // استراحة بالدقائق
    final breakMinutes = _safeMinutes(ws.breakMinutes ?? 0);

    // أوقات الشفت اختيارية هنا. إن أردت قصّ العمل داخل النافذة الفعلية فعّل القصّ أدناه.
    final startMin = _parseHmmToMin(ws.workStart) ?? 0;
    var endMin = _parseHmmToMin(ws.workEnd) ?? 0;
    final crossesMidnight = (endMin <= startMin);
    if (crossesMidnight) endMin += 24 * 60; // شفت لليوم التالي

    if (baseSalary <= 0 || totalWorkDaysInMonth <= 0) {
      final v = baseSalary > 0 ? baseSalary : 0.0;
      _remember(employeeId, v);
      return v;
    }

    double sumFractions = 0.0;

    for (final r in attendanceRecords) {
      final m = _asMap(r);
      final st = AttendanceStatus.normalize((m['status'] ?? '').toString());

      // إجازة مدفوعة = يوم كامل
      if (st == AttendanceStatus.paidLeave) {
        sumFractions += 1.0;
        continue;
      }

      // عطلة رسمية = يوم كامل إذا السياسة تسمح
      if (payOfficialHolidays && st == AttendanceStatus.holiday) {
        sumFractions += 1.0;
        continue;
      }

      // حضور فعلي
      if (st == AttendanceStatus.present) {
        // أولوية 1: ساعات جاهزة
        final hw = _toDouble(m['hoursWorked']);
        if (hw != null && hw > 0) {
          final workedMin = _safeMinutes((hw * 60).toInt());
          final afterBreak = math.max(0, workedMin - breakMinutes);
          sumFractions += _fractionOfDay(afterBreak, dayStdMinutes);
          continue;
        }

        // أولوية 2: حساب من checkIn/checkOut مع دعم الوردية الليلية
        final inStr = _asString(m['checkIn']);
        final outStr = _asString(m['checkOut']);

        if (inStr != null && outStr != null) {
          final ci0 = _parseHmmToMin(inStr);
          var co0 = _parseHmmToMin(outStr);
          if (ci0 != null && co0 != null) {
            var ci = ci0;
            var co = co0;
            if (co <= ci) co += 24 * 60; // خروج بعد منتصف الليل

            // خيار قصّ الحضور ضمن نافذة الشفت المحددة في الإعدادات:
            // إذا أردت عدم القصّ، علّق السطور الثلاثة التالية.
            final hasWindow = ws.workStart != null && ws.workEnd != null;
            if (hasWindow) {
              final s = startMin;
              final e = endMin; // قد تكون +24h
              ci = math.max(ci, s);
              co = math.min(co, e);
            }

            final rawWorked = math.max(0, co - ci);
            final afterBreak = math.max(0, rawWorked - breakMinutes);
            sumFractions += _fractionOfDay(afterBreak, dayStdMinutes);
            continue;
          }
        }

        // لا بيانات أوقات كافية ⇒ اعتبره يوم كامل
        sumFractions += 1.0;
      }
      // الغياب/الإجازة غير المدفوعة لا تضيف شيئًا
    }

    // سقف الأقصى = عدد أيام الشهر
    final maxFraction = totalWorkDaysInMonth.toDouble();
    if (sumFractions > maxFraction) sumFractions = maxFraction;

    final net = _fix2(baseSalary * (sumFractions / totalWorkDaysInMonth));
    _remember(employeeId, net);
    return net;
  }

  /// توافق خلفي مع الاستدعاء القديم
  Future<void> calculateSalaryFromAttendance({
    required String employeeId,
    required double baseSalary,
    required int totalWorkDaysInMonth,
    required List<dynamic> attendanceRecords,
  }) async {
    await calculateAndReturn(
      employeeId: employeeId,
      baseSalary: baseSalary,
      totalWorkDaysInMonth: totalWorkDaysInMonth,
      attendanceRecords: attendanceRecords,
      payOfficialHolidays: false,
    );
  }

  double getSalary(String employeeId) => _byEmployee[employeeId] ?? state;

  // ───────────── Helpers ─────────────

  void _remember(String employeeId, double net) {
    _byEmployee[employeeId] = net;
    state = net;
  }

  /// يحول أي سجل Attendance/Map إلى Map موحّد
  Map<String, dynamic> _asMap(dynamic r) {
    // 1) Map جاهز
    if (r is Map<String, dynamic>) return r;
    if (r is Map) {
      return r.map((k, v) => MapEntry(k.toString(), v));
    }

    // 2) نموذج Attendance مباشرة عبر الخصائص
    try {
      final status = r.status?.toString();
      final hoursWorked =
          (r.hoursWorked is num) ? (r.hoursWorked as num).toDouble() : null;
      final checkIn = r.checkIn?.toString();
      final checkOut = r.checkOut?.toString();
      if (status != null) {
        return {
          'status': status,
          'hoursWorked': hoursWorked,
          'checkIn': checkIn,
          'checkOut': checkOut,
        };
      }
    } catch (_) {}

    // 3) toMap()
    try {
      final m = Function.apply(r.toMap, const []) as Map?;
      if (m != null) {
        return m.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}

    // 4) toJson()
    try {
      final m = Function.apply(r.toJson, const []) as Map?;
      if (m != null) {
        return m.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}

    // 5) fallback
    return {'status': r.toString()};
  }

  String? _asString(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// "HH:mm" → دقائق منذ منتصف الليل
  int? _parseHmmToMin(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  int _safeMinutes(int x) => x < 0 ? 0 : x;

  double _fractionOfDay(int workedMinutesAfterBreak, int dayStdMinutes) {
    final denom = dayStdMinutes <= 0 ? 480 : dayStdMinutes; // fallback 8h
    final clamped = workedMinutesAfterBreak.clamp(0, denom);
    return clamped / denom;
  }

  double _fix2(num x) => double.parse(x.toStringAsFixed(2));
}
