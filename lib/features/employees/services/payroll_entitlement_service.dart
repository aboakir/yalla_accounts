import 'dart:convert';

import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

class PayrollEntitlementCalculation {
  final String employeeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double baseEarned;
  final double allowances;
  final double overtimePay;
  final double fixedDeductions;
  final double lateDeduction;
  final double earlyExitDeduction;
  final double netBeforeAdvances;
  final AttendanceSummary attendance;

  const PayrollEntitlementCalculation({
    required this.employeeId,
    required this.periodStart,
    required this.periodEnd,
    required this.baseEarned,
    required this.allowances,
    required this.overtimePay,
    required this.fixedDeductions,
    required this.lateDeduction,
    required this.earlyExitDeduction,
    required this.netBeforeAdvances,
    required this.attendance,
  });

  Map<String, Object?> toMap() => {
        'employeeId': employeeId,
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'baseEarned': baseEarned,
        'allowances': allowances,
        'overtimePay': overtimePay,
        'fixedDeductions': fixedDeductions,
        'lateDeduction': lateDeduction,
        'earlyExitDeduction': earlyExitDeduction,
        'netBeforeAdvances': netBeforeAdvances,
        'attendance': attendance.toMap(),
      };
}

class PayrollEntitlementService {
  PayrollEntitlementService._();

  static double _r(num value) => double.parse(value.toStringAsFixed(2));

  static Future<PayrollEntitlementCalculation> calculate({
    required Employee employee,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final attendance = await AttendanceDatabaseService
        .summarizeForPayrollUsingWorkshopSettings(
      employeeId: employee.id,
      from: periodStart,
      to: periodEnd,
    );
    final settings = await WorkshopSettingsService.instance.getOrDefaults();
    final policy = await AttendancePolicy.fromWorkshopSettings();

    if (attendance.scheduledWorkDays <= 0 || policy.hoursPerDay <= 0) {
      throw StateError('Workshop attendance schedule is not configured.');
    }

    final eligibleDays = attendance.presentDays +
        attendance.paidLeaveDays +
        attendance.holidayDays;
    final scheduledDays = attendance.scheduledWorkDays.toDouble();

    double baseEarned;
    if (employee.isDaily) {
      baseEarned = (employee.dailyRate ?? 0) * eligibleDays;
    } else if (employee.isWeekly) {
      final workDaysPerWeek =
          employee.workDaysPerWeek <= 0 ? 6 : employee.workDaysPerWeek;
      final dailyEquivalent = (employee.weeklyRate ?? 0) / workDaysPerWeek;
      baseEarned = dailyEquivalent * eligibleDays;
    } else {
      final periodBase = employee.isContract
          ? (employee.contractAmount ?? 0)
          : employee.baseSalary;
      baseEarned = periodBase * (eligibleDays / scheduledDays).clamp(0.0, 1.0);
    }

    final scheduledHours = scheduledDays * policy.hoursPerDay;
    final fallbackHourly = scheduledHours <= 0
        ? 0.0
        : (employee.isDaily
            ? (employee.dailyRate ?? 0) / policy.hoursPerDay
            : employee.isWeekly
                ? ((employee.weeklyRate ?? 0) /
                    (employee.workDaysPerWeek <= 0
                        ? 6
                        : employee.workDaysPerWeek) /
                    policy.hoursPerDay)
                : employee.baseSalary / scheduledHours);
    final hourlyRate =
        (settings.hourlyRate ?? 0) > 0 ? settings.hourlyRate! : fallbackHourly;

    final configuredOvertime = settings.overtimeRate ?? 0;
    final overtimePay = configuredOvertime > 5
        ? attendance.overtimeHours * configuredOvertime
        : AttendanceDatabaseService.computeOvertimeAddition(
            overtimeHours: attendance.overtimeHours,
            hourlyRate: hourlyRate,
            overtimeMultiplier:
                configuredOvertime > 0 ? configuredOvertime : 1.25,
          );
    final lateDeduction = AttendanceDatabaseService.computeLateDeduction(
      lateMinutes: attendance.lateMinutes,
      hourlyRate: hourlyRate,
    );
    final earlyExitDeduction = AttendanceDatabaseService.computeLateDeduction(
      lateMinutes: attendance.earlyExitMinutes,
      hourlyRate: hourlyRate,
    );

    final allowances = _r(employee.allowances);
    final fixedDeductions = _r(employee.deductions);
    final netBeforeAdvances = _r(
      baseEarned +
          allowances +
          overtimePay -
          fixedDeductions -
          lateDeduction -
          earlyExitDeduction,
    );
    if (netBeforeAdvances < 0) {
      throw StateError('Calculated salary entitlement cannot be negative.');
    }

    return PayrollEntitlementCalculation(
      employeeId: employee.id,
      periodStart: periodStart,
      periodEnd: periodEnd,
      baseEarned: _r(baseEarned),
      allowances: allowances,
      overtimePay: _r(overtimePay),
      fixedDeductions: fixedDeductions,
      lateDeduction: _r(lateDeduction),
      earlyExitDeduction: _r(earlyExitDeduction),
      netBeforeAdvances: netBeforeAdvances,
      attendance: attendance,
    );
  }

  static Future<String> accrueFromAttendance({
    required Employee employee,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime accrualDate,
    String? note,
  }) async {
    final calculation = await calculate(
      employee: employee,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    final attendanceSnapshot = jsonEncode(calculation.attendance.toMap());
    final basis = jsonEncode(calculation.toMap());

    return PayrollDatabaseService.accrue(
      employeeId: employee.id,
      periodStart: periodStart,
      periodEnd: periodEnd,
      accrualDate: accrualDate,
      gross: calculation.baseEarned,
      allowances: _r(calculation.allowances + calculation.overtimePay),
      deductions: _r(
        calculation.fixedDeductions +
            calculation.lateDeduction +
            calculation.earlyExitDeduction,
      ),
      advanceApplied: null,
      method: employee.paymentMethod,
      note: note,
      attendanceSnapshot: attendanceSnapshot,
      entitlementBasis: basis,
    );
  }
}
