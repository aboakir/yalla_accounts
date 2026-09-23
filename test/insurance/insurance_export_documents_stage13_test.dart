import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';
import 'package:yalla_accounts/features/insurance_agent/reports/services/insurance_report_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    AuthorizationGuard.disableInteractiveEnforcement();
    temp = await Directory.systemTemp.createTemp('insurance_stage13_export_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/stage13.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
  });

  tearDown(() async {
    AuthorizationGuard.disableInteractiveEnforcement();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  final policies = <InsurancePolicyOverview>[
    InsurancePolicyOverview(
      id: 'POL:1',
      number: 'POL-0001',
      insuredName: 'عميل، "اختبار"',
      vehicle: '12-3456 — Toyota',
      company: 'شركة التأمين، فلسطين',
      endDate: DateTime(2027, 9, 23),
      sale: 2400,
      status: 'ACTIVE',
    ),
    InsurancePolicyOverview(
      id: 'POL:2',
      number: 'POL-0002',
      insuredName: 'عميل ثانٍ',
      vehicle: '99-9999',
      company: 'شركة ب',
      endDate: DateTime(2027, 10, 1),
      sale: 1550.5,
      status: 'POSTED',
    ),
  ];

  test('stage13 CSV is UTF-8 Excel-safe and escapes Arabic content', () async {
    final csv = await InsuranceReportExportService.buildPoliciesCsv(policies);
    expect(csv.codeUnitAt(0), 0xFEFF);
    expect(csv, contains('"رقم الوثيقة"'));
    expect(csv, contains('"POL-0001"'));
    expect(csv, contains('"عميل، ""اختبار"""'));
    expect(csv, contains('"2400.00"'));
    expect(csv, contains('"1550.50"'));
    expect(csv.split('\n').where((line) => line.isNotEmpty).length, 3);
  });

  test('stage13 PDF export produces a real PDF document', () async {
    final pdf = await InsuranceReportExportService.buildPoliciesPdf(policies);
    expect(pdf.length, greaterThan(500));
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });
}
