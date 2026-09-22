import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/alerts/services/insurance_alert_center_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_alert_center_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> addAlert({
    required String id,
    required String type,
    required DateTime dueAt,
    required String status,
    String severity = 'NORMAL',
  }) async {
    final now = DateTime.utc(2026, 9, 22).toIso8601String();
    await db.insert('insurance_alerts', {
      'id': id,
      'alert_type': type,
      'due_at': dueAt.toIso8601String(),
      'status': status,
      'severity': severity,
      'message': id,
      'created_at': now,
      'updated_at': now,
    });
  }

  test('lists only open alerts in the selected date window', () async {
    final asOf = DateTime(2026, 9, 22);
    await addAlert(
      id: 'OVERDUE',
      type: 'POLICY_EXPIRY',
      dueAt: asOf.subtract(const Duration(days: 1)),
      status: 'OPEN',
      severity: 'HIGH',
    );
    await addAlert(
      id: 'TODAY',
      type: 'DRIVING_LICENSE_EXPIRY',
      dueAt: asOf,
      status: 'OPEN',
    );
    await addAlert(
      id: 'NEXT7',
      type: 'CHEQUE_DUE',
      dueAt: asOf.add(const Duration(days: 7)),
      status: 'OPEN',
    );
    await addAlert(
      id: 'CLOSED',
      type: 'POLICY_EXPIRY',
      dueAt: asOf,
      status: 'CLOSED',
    );

    final today = await InsuranceAlertCenterService.listAlerts(
      asOf: asOf,
      window: InsuranceAlertWindow.today,
      executor: db,
    );
    expect(today.map((item) => item.sourceId), contains('TODAY'));
    expect(today.map((item) => item.sourceId), isNot(contains('CLOSED')));

    final overdue = await InsuranceAlertCenterService.listAlerts(
      asOf: asOf,
      window: InsuranceAlertWindow.overdue,
      executor: db,
    );
    expect(overdue.map((item) => item.sourceId), contains('OVERDUE'));

    final next7 = await InsuranceAlertCenterService.listAlerts(
      asOf: asOf,
      window: InsuranceAlertWindow.next7,
      executor: db,
    );
    expect(next7.map((item) => item.sourceId), containsAll(['TODAY', 'NEXT7']));
    expect(next7.map((item) => item.sourceId), isNot(contains('OVERDUE')));
  });
}
