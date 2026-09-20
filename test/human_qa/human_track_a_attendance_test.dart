import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/services/attendance_reporting_service.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const policy = AttendancePolicy(
    hoursPerDay: 8,
    shiftStart: '09:00',
    shiftEnd: '17:00',
    weekWorkdays: '1,2,3,4,5',
  );

  Attendance row(
    String id,
    String employeeId,
    int day, {
    String status = AttendanceStatus.present,
    String? checkIn,
    String? checkOut,
    double? hours,
  }) =>
      Attendance(
        id: id,
        employeeId: employeeId,
        date: DateTime(2026, 9, day),
        status: status,
        checkIn: checkIn,
        checkOut: checkOut,
        hoursWorked: hours,
      );

  test('ATT-001..006 employee/range/totals are deterministic', () {
    final report = AttendanceReportingService.build(
      records: [
        row('a1', 'e1', 1, checkIn: '09:15', checkOut: '17:00'),
        row('a2', 'e1', 2, checkIn: '09:00', checkOut: '17:00', hours: 8),
        row('other', 'e2', 1, checkIn: '06:00', checkOut: '23:00'),
      ],
      employeeId: 'e1',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 4),
      policy: policy,
      asOf: DateTime(2026, 9, 4),
    );
    expect(report.days.length, 4);
    expect(
        report.days.every((d) =>
            !d.date.isBefore(DateTime(2026, 9, 1)) &&
            !d.date.isAfter(DateTime(2026, 9, 4))),
        isTrue);
    expect(report.presentDays, 2);
    expect(report.absentDays, 2);
    expect(report.totalWorkedHours, 15.75);
    expect(report.totalLateMinutes, 15);
    expect(report.days.where((d) => d.inferredAbsence).length, 2);

    final oneDay = AttendanceReportingService.build(
      records: [row('a2', 'e1', 2, hours: 8)],
      employeeId: 'e1',
      from: DateTime(2026, 9, 2),
      to: DateTime(2026, 9, 2),
      policy: policy,
      asOf: DateTime(2026, 9, 30),
    );
    expect(oneDay.days.single.date.day, 2);
    expect(oneDay.totalWorkedHours, 8);
  });

  test('ATT-002 month filter covers every calendar day', () {
    final report = AttendanceReportingService.build(
      records: const [],
      employeeId: 'e1',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
      policy: policy,
      asOf: DateTime(2026, 9, 30),
    );
    expect(report.days.length, 30);
    expect(report.days.first.date, DateTime(2026, 9, 1));
    expect(report.days.last.date, DateTime(2026, 9, 30));
  });

  test('ATT-010 no selected employee returns a clear empty data set', () {
    final report = AttendanceReportingService.build(
      records: const [],
      employeeId: '',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
      policy: policy,
    );
    expect(report.days, isEmpty);
    expect(report.presentDays, 0);
    expect(report.absentDays, 0);
  });

  test('ATT-007/008 report addition preserves today punch actions', () {
    final screen = File(
      'lib/features/employees/screens/attendance_screen.dart',
    ).readAsStringSync();
    expect(screen, contains('checkIn: currentHmm'));
    expect(screen, contains("reason: 'تسجيل انصراف فعلي'"));
    expect(screen, contains('تسجيل حضور اليوم'));
    expect(screen, contains('سجل / كشف الحضور'));
  });

  test('ATT report UI exposes employee month and custom range filters', () {
    final screen = File(
      'lib/features/employees/screens/attendance_report_screen.dart',
    ).readAsStringSync();
    expect(screen, contains("labelText: 'الموظف'"));
    expect(screen, contains("helpText: 'اختر شهر التقرير'"));
    expect(screen, contains("helpText: 'من تاريخ'"));
    expect(screen, contains("helpText: 'إلى تاريخ'"));
    expect(screen, contains('إجمالي ساعات العمل'));
    expect(screen, contains('غياب مستنتج'));
  });

  test('ATT-009 attendance survives database close and reopen', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('track_a_attendance_');
    final path = '${dir.path}/attendance.db';
    Database? db;
    Database? reopened;
    try {
      db = await DatabaseMigration.initDatabase(pathOverride: path);
      DatabaseMigration.useDatabaseForTesting(db);
      await EmployeeDatabaseService.insert(Employee.fromMap({
        'id': 'persist-e1',
        'employee_code': 'PE1',
        'full_name': 'Persist Employee',
        'status': 'active',
        'base_salary': 1000,
        'hire_date': '2026-01-01',
        'created_at': '2026-01-01',
      }));
      await AttendanceDatabaseService.insertAttendance(Attendance(
        id: 'persist-a1',
        employeeId: 'persist-e1',
        date: DateTime(2026, 9, 10),
        status: AttendanceStatus.present,
        checkIn: '09:00',
        checkOut: '17:00',
        hoursWorked: 8,
      ));
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      db = null;
      reopened = await DatabaseMigration.initDatabase(pathOverride: path);
      DatabaseMigration.useDatabaseForTesting(reopened);
      final rows = await AttendanceDatabaseService.getAttendanceForEmployee(
        employeeId: 'persist-e1',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );
      expect(rows.map((e) => e.id), contains('persist-a1'));
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db != null) await db.close();
      if (reopened != null) await reopened.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}
