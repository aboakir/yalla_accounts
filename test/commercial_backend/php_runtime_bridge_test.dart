import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_models.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

LicenseCheckResult license(
    String access, String status, String organizationId) {
  final now = DateTime.now().toUtc();
  return LicenseCheckResult(
    customerId: 'customer',
    customerCode: 'YA-TEST',
    accessMode: access,
    subscriptionStatus: status,
    deviceId: 'device',
    serverTime: now,
    leaseUntil: now.add(const Duration(days: 1)),
    leaseToken: null,
    organizationId: organizationId,
    subscriptionId: 'subscription',
    planCode: 'GARAGE_BASIC',
    planName: 'Garage Basic',
    startsAt: now.subtract(const Duration(days: 1)),
    expiresAt: now.add(const Duration(days: 30)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('PHP FULL projects WRITABLE and PHP READ_ONLY blocks SQL writes',
      () async {
    final dir = await Directory.systemTemp.createTemp('php_runtime_bridge_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    addTearDown(() async {
      CommercialBackendRuntimeAccess.reset();
      await db.close();
      await dir.delete(recursive: true);
    });

    final org = (await db.query('organizations')).single['id'] as String;
    final service = LicenseRuntimeService(databaseProvider: () async => db);

    CommercialBackendRuntimeAccess.applyLicense(license('FULL', 'ACTIVE', org));
    final writable = await service.refreshFromStoredLicense();
    expect(writable.mode, 'WRITABLE');
    await db.insert('clients', {'name': 'allowed', 'type': 'individual'});

    CommercialBackendRuntimeAccess.applyLicense(
      license('READ_ONLY', 'GRACE', org),
    );
    final readOnly = await service.refreshFromStoredLicense();
    expect(readOnly.isReadOnly, isTrue);
    await expectLater(
      db.insert('clients', {'name': 'blocked', 'type': 'individual'}),
      throwsA(anything),
    );
    expect((await db.query('clients')).length, 1);
  });
}
