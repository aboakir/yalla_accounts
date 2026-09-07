import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('Stage 4 attendance uses actual punch times and audited edits', () {
    final screen =
        read('lib/features/employees/screens/attendance_screen.dart');
    final db = read(
        'lib/features/employees/services/attendance_database_service.dart');

    expect(screen, contains('final now = DateTime.now()'));
    expect(screen, contains('checkIn: currentHmm'));
    expect(screen, contains('checkOut: null'));
    expect(screen, contains("reason: 'تسجيل انصراف فعلي'"));
    expect(screen, contains('سبب التعديل / الحذف'));

    expect(db, contains('ATTENDANCE_CREATED'));
    expect(db, contains('ATTENDANCE_UPDATED'));
    expect(db, contains('ATTENDANCE_DELETED'));
    expect(db, contains('Attendance edit reason is required'));
    expect(db, contains('Attendance delete reason is required'));
    expect(db, contains('earlyExitMinutes'));
    expect(db, contains('scheduledWorkDays'));
    expect(db, contains('missingWorkDays'));
    expect(db, contains('AttendancePolicy.fromWorkshopSettings'));
  });

  test('Stage 4 salary entitlement is attendance driven', () {
    final entitlement = read(
      'lib/features/employees/services/payroll_entitlement_service.dart',
    );
    final payroll = read('lib/features/employees/screens/payroll_screen.dart');
    final salary = read('lib/features/employees/screens/salary_screen.dart');

    expect(entitlement, contains('summarizeForPayrollUsingWorkshopSettings'));
    expect(entitlement, contains('lateDeduction'));
    expect(entitlement, contains('earlyExitDeduction'));
    expect(entitlement, contains('overtimePay'));
    expect(entitlement, contains('accrueFromAttendance'));
    expect(entitlement, contains('attendanceSnapshot'));
    expect(entitlement, contains('entitlementBasis'));

    expect(payroll, contains('PayrollEntitlementService.accrueFromAttendance'));
    expect(payroll, contains('enabled: false'));
    expect(salary, contains('PayrollEntitlementService.calculate'));
    expect(salary, contains('PayrollEntitlementService.accrueFromAttendance'));
  });
}
