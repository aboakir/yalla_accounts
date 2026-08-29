import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('yalla_sec011_runtime_');
  });

  tearDown(() async {
    await DatabaseMigration.closeDatabase(checkpoint: false);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('READ ONLY blocks business writes but keeps auth metadata writable',
      () async {
    final path = '${tempDir.path}/runtime.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    addTearDown(() async {
      if (db.isOpen) await db.close();
    });

    final now = DateTime.now().toUtc().toIso8601String();
    final userId = const Uuid().v4();
    await db.insert('users', {
      'id': userId,
      'name': 'sec011-owner',
      'password': 'test-only-hash',
      'role': 'owner',
      'status': 'active',
      'created_at': now,
      'is_owner': 1,
      'must_change_password': 0,
      'failed_login_count': 0,
      'organization_id':
          (await db.query('organizations', limit: 1)).first['id'],
    });

    await db.execute(
      'CREATE TABLE sec011_probe_business('
      'id INTEGER PRIMARY KEY, value TEXT)',
    );
    await LicenseRuntimeTables.installOperationalTriggers(db);

    await db.update(
      LicenseRuntimeTables.table,
      {
        'mode': LicenseRuntimeMode.readOnlyExpired,
        'reason': 'test expiry',
        'updated_at': now,
      },
      where: 'singleton_id = 1',
    );

    await expectLater(
      db.insert('sec011_probe_business', {'value': 'blocked'}),
      throwsA(isA<sq.DatabaseException>()),
    );

    // Reading remains available.
    expect(await db.query('sec011_probe_business'), isEmpty);

    // Login bookkeeping remains available.
    expect(
      await db.update(
        'users',
        {'last_login_at': now, 'failed_login_count': 0},
        where: 'id = ?',
        whereArgs: [userId],
      ),
      1,
    );

    // Business identity/role changes are blocked.
    await expectLater(
      db.update(
        'users',
        {'role': 'manager'},
        where: 'id = ?',
        whereArgs: [userId],
      ),
      throwsA(isA<sq.DatabaseException>()),
    );

    // New users are explicitly blocked.
    await expectLater(
      db.insert('users', {
        'id': const Uuid().v4(),
        'name': 'sec011-second',
        'password': 'test-only-hash',
      }),
      throwsA(isA<sq.DatabaseException>()),
    );
  });

  test('WRITABLE mode permits business writes', () async {
    final path = '${tempDir.path}/writable.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    addTearDown(() async {
      if (db.isOpen) await db.close();
    });

    await db.execute(
      'CREATE TABLE sec011_probe_business('
      'id INTEGER PRIMARY KEY, value TEXT)',
    );
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.update(
      LicenseRuntimeTables.table,
      {
        'mode': LicenseRuntimeMode.writable,
        'reason': 'test active license',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'singleton_id = 1',
    );

    expect(
      await db.insert('sec011_probe_business', {'value': 'allowed'}),
      1,
    );
  });
}
