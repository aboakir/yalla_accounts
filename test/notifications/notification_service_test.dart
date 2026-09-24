import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/experience/app_experience_profile.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/notifications/models/app_notification.dart';
import 'package:yalla_accounts/features/notifications/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late Database db;
  final now = DateTime(2026, 9, 24, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('notifications_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    await NotificationService.resetPresentationStateForTesting();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> seedRepairAndReceivable() async {
    await db.insert('repairs', {
      'id': 'R-NOTIFY-1',
      'receivedDate': '2026-09-01',
      'vehicleNumber': '123-45-678',
      'status': 'APPROVED',
      'vehicleStatus': 'قيد الإصلاح',
    });
    await db.insert('invoices', {
      'id': 'INV-NOTIFY-1',
      'date': '2026-08-01',
      'total': 900.0,
      'paid': 100.0,
      'status': 'UNPAID',
      'created_at': '2026-08-01T10:00:00',
    });
  }

  test('real DB sources create repair and receivable notifications', () async {
    await seedRepairAndReceivable();

    final items = await NotificationService.loadOn(
      db,
      profile: AppExperienceProfile.defaults,
      now: now,
    );

    expect(items.any((e) => e.key.startsWith('repair:R-NOTIFY-1')), isTrue);
    final receivable =
        items.singleWhere((e) => e.key == 'receivable:INV-NOTIFY-1');
    expect(receivable.sourceType, 'receivables');
    expect(receivable.route, isNotNull);
    expect(receivable.status, AppNotificationStatus.overdue);
  });

  test('module visibility filters hidden activity sources', () async {
    await seedRepairAndReceivable();
    const partsOnly = AppExperienceProfile(
      activities: <BusinessActivity>{BusinessActivity.parts},
      mode: ExperienceMode.simple,
      moduleOverrides: <AppModule, bool>{
        AppModule.repairs: false,
        AppModule.finance: false,
      },
    );

    final items = await NotificationService.loadOn(
      db,
      profile: partsOnly,
      now: now,
    );

    expect(items.where((e) => e.sourceType == 'repairs'), isEmpty);
    expect(items.where((e) => e.sourceType == 'receivables'), isEmpty);
  });

  test('read and handled state survives reload without changing source rows',
      () async {
    await seedRepairAndReceivable();
    var items = await NotificationService.loadOn(
      db,
      profile: AppExperienceProfile.defaults,
      now: now,
    );
    final target = items.firstWhere((e) => e.sourceType == 'receivables');

    await NotificationService.markRead(target.key);
    items = await NotificationService.loadOn(
      db,
      profile: AppExperienceProfile.defaults,
      now: now,
    );
    expect(items.firstWhere((e) => e.key == target.key).isRead, isTrue);

    await NotificationService.markHandled(target.key);
    items = await NotificationService.loadOn(
      db,
      profile: AppExperienceProfile.defaults,
      now: now,
    );
    final handled = items.firstWhere((e) => e.key == target.key);
    expect(handled.status, AppNotificationStatus.handled);

    final invoiceRows = await db.query(
      'invoices',
      where: 'id=?',
      whereArgs: const ['INV-NOTIFY-1'],
    );
    expect(invoiceRows, hasLength(1));
    expect((invoiceRows.single['paid'] as num).toDouble(), 100.0);
  });
}
