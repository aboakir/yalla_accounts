import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('SEC.005 migrates live DB v63 to v64 without historical rewrites',
      () async {
    final path = Platform.environment['YALLA_SEC005_LIVE_DB_PATH']?.trim();
    if (path == null || path.isEmpty) {
      throw StateError('YALLA_SEC005_LIVE_DB_PATH is required.');
    }

    final before =
        await sq.openDatabase(path, readOnly: true, singleInstance: false);
    late int usersBefore;
    late String organizationId;
    try {
      final version = await before.getVersion();
      expect(version, anyOf(63, 64, 65));
      usersBefore = sq.Sqflite.firstIntValue(
            await before.rawQuery('SELECT COUNT(*) FROM users'),
          ) ??
          0;
      final org = await before.query(
        'organization_identity',
        columns: ['organization_id'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      organizationId = org.single['organization_id']!.toString();
    } finally {
      await before.close();
    }

    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(64));
      final usersAfter = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM users'),
          ) ??
          0;
      expect(usersAfter, usersBefore);

      final org = await db.query(
        'organization_identity',
        columns: ['organization_id'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      expect(org.single['organization_id'], organizationId);

      final table = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='installation_identity'",
      );
      expect(table.length, 1);
      // SEC.005 schema migration does not fabricate a device key in SQLite.
      // Materialization occurs through DeviceIdentityService using secure storage.
      final identityCount = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM installation_identity'),
          ) ??
          0;
      expect(identityCount, anyOf(0, 1));

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first.toString(), 'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      // ignore: avoid_print
      print('SEC005_DB_VERSION=${await db.getVersion()}');
      // ignore: avoid_print
      print('SEC005_ORGANIZATION_ID=$organizationId');
      // ignore: avoid_print
      print('SEC005_USERS_PRESERVED=$usersAfter');
      // ignore: avoid_print
      print('SEC005_INSTALLATION_IDENTITY_ROWS=$identityCount');
      // ignore: avoid_print
      print('SEC005_INTEGRITY=ok');
      // ignore: avoid_print
      print('SEC005_FOREIGN_KEYS=ok');
    } finally {
      await db.close();
    }
  });
}
