import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';
import 'package:yalla_accounts/features/employees/screens/edit_employee_screen.dart';
import 'package:yalla_accounts/features/settings/widgets/work_schedule_fields.dart';
import 'workflow_widgets_test.dart' show app, flush, tap, field;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('workdays hours break and overtime can be edited on a phone',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var days = '1,2,3,4,5';
    var hours = 8.0;
    var pause = 0;
    var extra = 1.25;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (ctx, set) => SingleChildScrollView(
                    child: WorkScheduleFields(
                        days: days,
                        hours: hours,
                        breakMinutes: pause,
                        overtime: extra,
                        onDays: (v) => set(() => days = v),
                        onHours: (v) => hours = v,
                        onBreak: (v) => pause = v,
                        onOvertime: (v) => extra = v))))));
    await t.tap(find.widgetWithText(FilterChip, 'الجمعة'));
    await t.pump();
    await t.tap(find.widgetWithText(FilterChip, 'الأحد'));
    await t.pump();
    await t.enterText(field('ساعات العمل اليومية المدفوعة'), '7');
    await t.enterText(field('الاستراحة غير المدفوعة بالدقائق'), '60');
    await t.enterText(field('معدل الإضافي'), '0');
    expect(days, '1,2,3,4,7');
    expect(hours, 7);
    expect(pause, 60);
    expect(extra, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('edit employee preserves inactive status and updates weekly rate',
      (t) async {
    t.view.physicalSize = const Size(430, 932);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    late Directory dir;
    late Database db;
    late Employee employee;
    await t.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('employee_widget_');
      db = await DatabaseMigration.initDatabase(
          pathOverride: '${dir.path}/test.db');
      DatabaseMigration.useDatabaseForTesting(db);
      employee = Employee.fromMap({
        'id': 'e1',
        'employee_code': 'E1',
        'full_name': 'Worker',
        'status': 'inactive',
        'base_salary': 2200,
        'hire_date': '2026-01-01',
        'created_at': '2026-01-01'
      });
      await EmployeeDatabaseService.insert(employee);
    });
    try {
      await t.pumpWidget(app(Builder(
          builder: (ctx) => Scaffold(
              body: TextButton(
                  onPressed: () => Navigator.of(ctx).push(
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              EditEmployeeScreen(employee: employee))),
                  child: const Text('open'))))));
      await tap(t, find.text('open'));
      await tap(t, find.byType(DropdownButtonFormField<EmployeeContractType>));
      await tap(t, find.text('أسبوعي').last);
      await t.enterText(field('الراتب الأساسي'), '500');
      t.testTextInput.hide();
      await tap(t, find.text('حفظ التعديلات'));
      await flush(t);
      final saved =
          await t.runAsync(() => EmployeeDatabaseService.getById('e1'));
      expect(saved!.status, 'inactive');
      expect(saved.contractType, EmployeeContractType.weekly);
      expect(saved.weeklyRate, 500);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await flush(t);
      DatabaseMigration.useDatabaseForTesting(null);
      await t.runAsync(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
    }
  });
}
