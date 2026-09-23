import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/screens/advances_report_screen.dart';
import 'package:yalla_accounts/features/employees/screens/attendance_report_screen.dart';
import 'package:yalla_accounts/features/employees/screens/payroll_report_screen.dart';
import 'package:yalla_accounts/features/employees/screens/salary_screen.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';

import '../responsive/stage36_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(loadAuditFonts);

  testWidgets('payroll reports fit 320px RTL phone with canonical data',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late Directory dir;
    late Database db;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('payroll_phone_');
      db = await DatabaseMigration.initDatabase(
        pathOverride: p.join(dir.path, 'phone.db'),
      );
      DatabaseMigration.useDatabaseForTesting(db);
      await seedAuditData(db);
      await EmployeeDatabaseService.insert(Employee.fromMap({
        'id': 'win-e1',
        'employee_code': 'WIN-E1',
        'full_name': 'ظ…ظˆط¸ظپ ط§ط®طھط¨ط§ط± ط§ظ„ط±ظˆط§طھط¨ ط¹ظ„ظ‰ ظˆظٹظ†ط¯ظˆط²',
        'hire_date': '2026-01-01',
        'created_at': '2026-01-01',
        'status': 'active',
        'base_salary': 1800,
        'contract_type': 'monthly',
      }));
      await PayrollDatabaseService.accrue(
        employeeId: 'win-e1',
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        accrualDate: DateTime(2026, 9, 30),
        gross: 1800,
      );
    });
    addTearDown(() async {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    for (final screen in <Widget>[
      const SalaryScreen(),
      const PayrollReportScreen(),
      const AdvancesReportScreen(),
      const AttendanceReportScreen(),
    ]) {
      await tester.pumpWidget(auditApp(screen));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 1000));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.takeException(),
        isNull,
        reason: 'phone layout failed for ${screen.runtimeType}',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'phone layout failed for ${screen.runtimeType}',
      );
    }
  });
}
