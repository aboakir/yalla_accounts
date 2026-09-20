import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String dbPath;
  late Database db;

  Map<String, Object?> employee(String id, String code) => {
        'id': id,
        'full_name': 'Employee $code',
        'employee_code': code,
        'job_title': 'Painter',
        'hire_date': '2026-01-01',
        'phone': '',
        'email': '',
        'address': '',
        'status': 'active',
        'base_salary': 1200.0,
        'allowances': 0.0,
        'deductions': 0.0,
        'advances': 0.0,
        'total_work_days': 0,
        'total_hours': 0.0,
        'absences': 0,
        'late_days': 0,
        'notes': '',
        'created_at': '2026-01-01T00:00:00Z',
        'payment_method': 'cash',
        'work_days_per_week': 5,
        'hours_per_day': 8,
      };

  Future<void> attendance(
    String id,
    String employeeId,
    DateTime day,
    String status, {
    String? checkIn,
    String? checkOut,
    double? hours,
  }) =>
      db.insert('attendance', {
        'id': id,
        'employeeId': employeeId,
        'date': day.toIso8601String(),
        'status': status,
        'checkIn': checkIn,
        'checkOut': checkOut,
        'hoursWorked': hours,
        'notes': '',
      });

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('human_att_gate_');
    dbPath = '${temp.path}/test.db';
    db = await DatabaseMigration.initDatabase(pathOverride: dbPath);

    await db.insert('employees', employee('E1', 'E-1'));
    await db.insert('employees', employee('E2', 'E-2'));

    await attendance(
      'A1',
      'E1',
      DateTime(2026, 9, 14),
      'حضور',
      checkIn: '09:00',
      checkOut: '17:00',
      hours: 8,
    );
    await attendance('A2', 'E1', DateTime(2026, 9, 15), 'غياب');
    await attendance(
      'A3',
      'E1',
      DateTime(2026, 9, 16),
      'حضور',
      checkIn: '10:00',
      checkOut: '16:00',
      hours: 6,
    );
    await attendance(
      'B1',
      'E2',
      DateTime(2026, 9, 14),
      'حضور',
      checkIn: '09:00',
      checkOut: '17:00',
      hours: 8,
    );
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('TEST-ATT-001 selected employee returns only their records', () async {
    final rows = await AttendanceDatabaseService.getAttendanceForEmployee(
      employeeId: 'E1',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30, 23, 59, 59),
      executor: db,
    );
    expect(rows, hasLength(3));
    expect(rows.every((row) => row.employeeId == 'E1'), isTrue);
  });

  test('TEST-ATT-002 selected month returns all correct month records',
      () async {
    final rows = await AttendanceDatabaseService.getAttendanceForEmployee(
      employeeId: 'E1',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30, 23, 59, 59),
      executor: db,
    );
    expect(
      rows.map((row) => row.date.day).toList(),
      [14, 15, 16],
    );
  });

  test('TEST-ATT-003 custom date range respects both boundaries', () async {
    final rows = await AttendanceDatabaseService.getAttendanceForEmployee(
      employeeId: 'E1',
      from: DateTime(2026, 9, 14),
      to: DateTime(2026, 9, 15, 23, 59, 59),
      executor: db,
    );
    expect(rows.map((row) => row.date.day).toList(), [14, 15]);
  });

  test('TEST-ATT-004 records outside range are excluded', () async {
    final rows = await AttendanceDatabaseService.getAttendanceForEmployee(
      employeeId: 'E1',
      from: DateTime(2026, 9, 14),
      to: DateTime(2026, 9, 15, 23, 59, 59),
      executor: db,
    );
    expect(rows.any((row) => row.date.day == 16), isFalse);
  });

  const policy = AttendancePolicy(
    hoursPerDay: 8,
    shiftStart: '09:00',
    shiftEnd: '17:00',
    weekWorkdays: '1,2,3,4,5',
  );

  test('TEST-ATT-005 total worked hours equals displayed record sum', () async {
    final summary = await AttendanceDatabaseService.summarizeForPayroll(
      employeeId: 'E1',
      from: DateTime(2026, 9, 14),
      to: DateTime(2026, 9, 16, 23, 59, 59),
      policy: policy,
      executor: db,
    );
    expect(summary.workedHours, 14.0);
    expect(summary.lateMinutes, 60);
    expect(summary.earlyExitMinutes, 60);
  });

  test('TEST-ATT-006 present and absent day totals are correct', () async {
    final summary = await AttendanceDatabaseService.summarizeForPayroll(
      employeeId: 'E1',
      from: DateTime(2026, 9, 14),
      to: DateTime(2026, 9, 16, 23, 59, 59),
      policy: policy,
      executor: db,
    );
    expect(summary.presentDays, 2);
    expect(summary.absentDays, 1);
    expect(summary.scheduledWorkDays, 3);
    expect(summary.missingWorkDays, 0);
  });

  test('TEST-ATT-007 today registration path remains active', () {
    final source = File(
      'lib/features/employees/screens/attendance_screen.dart',
    ).readAsStringSync();
    expect(source, contains("'تسجيل حضور / انصراف اليوم'"));
    expect(
      source,
      contains('AttendanceDatabaseService.insertAttendance(rec)'),
    );
    expect(
      source,
      contains('AttendanceDatabaseService.updateAttendance('),
    );
    expect(
      source,
      contains('final todayRows = await AttendanceDatabaseService'),
    );
  });
  test('TEST-ATT-008 reopening database preserves attendance records',
      () async {
    await db.close();
    db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
    final rows = await AttendanceDatabaseService.getAttendanceForEmployee(
      employeeId: 'E1',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30, 23, 59, 59),
      executor: db,
    );
    expect(rows, hasLength(3));
    expect(rows.map((row) => row.id).toSet(), {'A1', 'A2', 'A3'});
  });

  test('attendance UI exposes monthly and custom report controls', () {
    final source = File(
      'lib/features/employees/screens/attendance_screen.dart',
    ).readAsStringSync();
    expect(source, contains("'كشف وسجل الحضور'"));
    expect(source, contains("'اختيار شهر'"));
    expect(source, contains("'فترة مخصصة'"));
    expect(source, contains("'إجمالي ساعات العمل'"));
    expect(source, contains('_periodDays'));
  });
}
