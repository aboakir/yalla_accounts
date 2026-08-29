import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/license_validation_tables.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('yalla_sec012_grace_');
  });

  tearDown(() async {
    await DatabaseMigration.closeDatabase(checkpoint: false);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
      'DB blocks writes after validation grace even if runtime row is writable',
      () async {
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${tempDir.path}/grace.db',
    );
    addTearDown(() async {
      if (db.isOpen) await db.close();
    });

    final now = DateTime.now().toUtc();
    await LicenseValidationTables.projectSignedWindow(
      db,
      organizationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      licenseId: '11111111-1111-4111-8111-111111111111',
      validationRequiredAt: now.subtract(const Duration(days: 2)),
      validationGraceUntil: now.subtract(const Duration(seconds: 1)),
    );
    await db.update(
      LicenseRuntimeTables.table,
      <String, Object?>{
        'mode': LicenseRuntimeMode.writable,
        'reason': 'stale writable projection for enforcement test',
        'updated_at': now.toIso8601String(),
      },
      where: 'singleton_id = 1',
    );

    await db.execute(
      'CREATE TABLE sec012_probe_business(id INTEGER PRIMARY KEY, value TEXT)',
    );
    await LicenseRuntimeTables.installOperationalTriggers(db);

    await expectLater(
      db.insert('sec012_probe_business', <String, Object?>{'value': 'blocked'}),
      throwsA(isA<sq.DatabaseException>()),
    );
    expect(await db.query('sec012_probe_business'), isEmpty);
  });
}
