import 'package:yalla_accounts/features/employees/services/salary_database_service.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/providers/salary_provider.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';
import 'package:yalla_accounts/features/employees/services/employee_service.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_entitlement_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';
import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'employee CRUD, attendance, entitlement, advance, bonus and salary share GL',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('payroll_regression_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'payroll-owner');
    try {
      var employee = Employee.fromMap({
        'id': 'e1',
        'employee_code': 'E1',
        'full_name': 'Worker',
        'hire_date': '2026-01-01',
        'created_at': '2026-01-01',
        'status': 'active',
        'base_salary': 2200,
        'allowances': 22,
        'deductions': 11,
        'contract_type': 'monthly'
      });
      await EmployeeDatabaseService.insert(employee);
      await expectLater(
          EmployeeDatabaseService.insert(employee.copyWith(id: 'e2')),
          throwsA(isA<DatabaseException>()));
      employee = employee.copyWith(fullName: 'Updated', status: 'inactive');
      await EmployeeDatabaseService.update(employee);
      expect((await EmployeeDatabaseService.getById('e1'))!.status, 'inactive');
      employee = employee.copyWith(status: 'active');
      await EmployeeDatabaseService.update(employee);
      const settings = WorkshopSettings(
          workStart: '09:00',
          workEnd: '17:00',
          dailyHours: 8,
          breakMinutes: 0,
          weekWorkdays: '1,2,3,4,5',
          overtimeRate: 1.5);
      await WorkshopSettingsService.instance.saveSettings(settings);
      Attendance row(int day, String status, {String? start, String? end}) =>
          Attendance(
              id: 'day$day',
              employeeId: 'e1',
              date: DateTime(2026, 9, day),
              status: status,
              checkIn: start,
              checkOut: end);
      await AttendanceDatabaseService.insertAttendance(
          row(1, 'حاضر', start: '09:00', end: '17:00'));
      await AttendanceDatabaseService.insertAttendance(
          row(2, 'حاضر', start: '10:00', end: '17:00'));
      await AttendanceDatabaseService.insertAttendance(
          row(3, 'حاضر', start: '09:00', end: '19:00'));
      await AttendanceDatabaseService.insertAttendance(row(4, 'غائب'));
      await expectLater(
          AttendanceDatabaseService.insertAttendance(
              row(1, 'حاضر').copyWith(id: 'duplicate')),
          throwsStateError);
      await EmployeeDatabaseService.upsert(
          employee.copyWith(fullName: 'Safe update'));
      expect((await db.query('attendance')).length, 4);
      final from = DateTime(2026, 9, 1), to = DateTime(2026, 9, 30);
      Future<PayrollEntitlementCalculation> calc(Employee e) =>
          PayrollEntitlementService.calculate(
              employee: e, periodStart: from, periodEnd: to);
      final calculation = await calc(employee);
      expect(calculation.attendance.scheduledWorkDays, 22);
      expect(calculation.attendance.absentDays, 19);
      expect(calculation.attendance.workedHours, 25);
      expect(calculation.lateDeduction, 12.5);
      expect(calculation.overtimePay, 37.5);
      expect(calculation.netBeforeAdvances, 336);
      expect(
          (await calc(employee.copyWith(
                  contractType: EmployeeContractType.daily, dailyRate: 100)))
              .netBeforeAdvances,
          336);
      expect(
          (await calc(employee.copyWith(
                  contractType: EmployeeContractType.weekly,
                  weeklyRate: 500,
                  workDaysPerWeek: 6)))
              .netBeforeAdvances,
          336);
      final provider = SalaryNotifier();
      expect(
          await provider.calculateAndReturn(
              employeeId: 'e1',
              baseSalary: 999999,
              totalWorkDaysInMonth: 30,
              attendanceRecords: [],
              periodStart: from,
              periodEnd: to),
          336);
      provider.dispose();
      Future<void> voucher(String id, String source, double amount,
          {String? run}) async {
        await VoucherPaymentService.insertAndPost(
            voucher: VoucherPayment(
                id: id,
                voucherType: 'PAYMENT',
                partyType: 'EMPLOYEE',
                partyId: 'e1',
                amount: amount,
                currency: 'ILS',
                date: DateTime(2026, 9, 30),
                method: 'cash',
                source: source,
                sourceId: run ?? id,
                reference: run),
            partyName: 'Worker');
      }

      await voucher('advance', 'EMP_ADV', 20);
      await voucher('bonus', 'EMPLOYEE_BONUS', 50);
      Future<double> balance(String code) async => ((await db.rawQuery(
                  'SELECT COALESCE(SUM(l.debit-l.credit),0) n FROM gl_lines l JOIN accounts a ON a.id=l.account_id WHERE a.code=?',
                  [code]))
              .single['n'] as num)
          .toDouble();
      expect(await balance('1120.Ee1'), 20);
      expect(await balance('5100'), 50);
      await db.execute(
          "CREATE TRIGGER fail_payroll BEFORE INSERT ON gl_entries WHEN NEW.source='PAYROLL_ACCRUAL' BEGIN SELECT RAISE(ABORT, 'test posting failure'); END");
      await expectLater(
          PayrollEntitlementService.accrueFromAttendance(
              employee: employee,
              periodStart: from,
              periodEnd: to,
              accrualDate: to),
          throwsA(isA<DatabaseException>()));
      expect(await db.query('payroll_runs'), isEmpty);
      expect(await db.query('salaries'), isEmpty);
      expect(await balance('1120.Ee1'), 20);
      await db.execute('DROP TRIGGER fail_payroll');
      final run = await PayrollEntitlementService.accrueFromAttendance(
          employee: employee,
          periodStart: from,
          periodEnd: to,
          accrualDate: to);
      expect((await PayrollDatabaseService.getById(run))!.net, 316);
      expect(await balance('1120.Ee1'), 0);
      await db.update('salary_periods', {'is_locked': 1});
      await expectLater(voucher('locked', 'PAYROLL_ENTITLEMENT', 100, run: run),
          throwsStateError);
      await db.update('salary_periods', {'is_locked': 0});
      await voucher('salary', 'PAYROLL_ENTITLEMENT', 100, run: run);
      expect((await PayrollDatabaseService.getById(run))!.amountPaid, 100);
      expect(await balance('2140.Ee1'), -216);
      final report = (await SalaryDatabaseService.getSalary(
          employeeId: 'e1', month: '2026-09'))!;
      expect(report.paid, 100);
      expect(report.due, 216);
      expect(
          (await SalaryDatabaseService.getSalariesByMonth('2026-09'))
              .single
              .paid,
          100);
      expect(await balance('1000'), -170);
      await expectLater(
          voucher('overpay', 'PAYROLL_ENTITLEMENT', 217, run: run),
          throwsStateError);
      await expectLater(
          PayrollEntitlementService.accrueFromAttendance(
              employee: employee,
              periodStart: from,
              periodEnd: to,
              accrualDate: to),
          throwsStateError);
      await expectLater(
          EmployeeService.paySalary(employeeId: 'e1', amount: 10, payDate: to),
          throwsStateError);
      final totals = await db.rawQuery(
          'SELECT entry_id FROM gl_lines GROUP BY entry_id HAVING ABS(SUM(debit-credit))>0.001');
      expect(totals, isEmpty);
      final legacyTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='salary_payments'");
      if (legacyTables.isNotEmpty)
        expect(await db.query('salary_payments'), isEmpty);
      await session.endEphemeralPreviewSession();
      await db.close();
      final reopened =
          await databaseFactoryFfi.openDatabase('${dir.path}/test.db');
      DatabaseMigration.useDatabaseForTesting(reopened);
      expect((await EmployeeDatabaseService.getById('e1'))!.fullName,
          'Safe update');
      expect(
          (await WorkshopSettingsService.instance.getOrDefaults()).weekWorkdays,
          '1,2,3,4,5');
      await reopened.close();
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });
  test('night shift, holidays, incomplete punches and schedule validation',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('night_payroll_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'night-owner');
    try {
      final employee = Employee.fromMap({
        'id': 'night',
        'employee_code': 'N1',
        'full_name': 'Night worker',
        'base_salary': 2200,
        'hire_date': '2026-01-01',
        'created_at': '2026-01-01'
      });
      await EmployeeDatabaseService.insert(employee);
      const schedule = WorkshopSettings(
          workStart: '22:00',
          workEnd: '06:00',
          dailyHours: 8,
          breakMinutes: 0,
          weekWorkdays: '1,2,3,4,5',
          overtimeRate: 0);
      await WorkshopSettingsService.instance.saveSettings(schedule);
      await AttendanceDatabaseService.insertAttendance(Attendance(
          id: 'night1',
          employeeId: 'night',
          date: DateTime(2026, 9, 1),
          status: 'حاضر',
          checkIn: '23:00',
          checkOut: '05:00'));
      final result = await PayrollEntitlementService.calculate(
          employee: employee,
          periodStart: DateTime(2026, 9, 1),
          periodEnd: DateTime(2026, 9, 30));
      expect(result.attendance.lateMinutes, 60);
      expect(result.attendance.earlyExitMinutes, 60);
      expect(result.netBeforeAdvances, 75);
      for (final entry in {3: 'إجازة_مدفوعة', 4: 'عطلة_رسمية'}.entries) {
        await AttendanceDatabaseService.insertAttendance(Attendance(
            id: 'leave${entry.key}',
            employeeId: 'night',
            date: DateTime(2026, 9, entry.key),
            status: entry.value));
      }
      await AttendanceDatabaseService.insertAttendance(Attendance(
          id: 'weekend',
          employeeId: 'night',
          date: DateTime(2026, 9, 5),
          status: 'حاضر',
          checkIn: '22:00',
          checkOut: '06:00'));
      final holiday = await PayrollEntitlementService.calculate(
          employee: employee,
          periodStart: DateTime(2026, 9, 1),
          periodEnd: DateTime(2026, 9, 30));
      expect(holiday.baseEarned, 300);
      expect(holiday.overtimePay, 0);
      expect(holiday.netBeforeAdvances, 275);
      await expectLater(
          WorkshopSettingsService.instance
              .saveSettings(schedule.copyWith(weekWorkdays: '')),
          throwsArgumentError);
      await expectLater(
          WorkshopSettingsService.instance
              .saveSettings(schedule.copyWith(dailyHours: 9)),
          throwsArgumentError);
      await AttendanceDatabaseService.insertAttendance(Attendance(
          id: 'open',
          employeeId: 'night',
          date: DateTime(2026, 9, 2),
          status: 'حاضر',
          checkIn: '22:00'));
      await expectLater(
          PayrollEntitlementService.calculate(
              employee: employee,
              periodStart: DateTime(2026, 9, 1),
              periodEnd: DateTime(2026, 9, 30)),
          throwsStateError);
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
