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

  test('SEC.006 migrates live DB v64 to v65 without historical rewrites',
      () async {
    final path = Platform.environment['YALLA_SEC006_LIVE_DB_PATH']?.trim();
    if (path == null || path.isEmpty) {
      throw StateError('YALLA_SEC006_LIVE_DB_PATH is required.');
    }

    final before =
        await sq.openDatabase(path, readOnly: true, singleInstance: false);
    late int usersBefore;
    late int glBefore;
    late String organizationId;
    try {
      expect(await before.getVersion(), 64);
      usersBefore = sq.Sqflite.firstIntValue(
            await before.rawQuery('SELECT COUNT(*) FROM users'),
          ) ??
          0;
      glBefore = sq.Sqflite.firstIntValue(
            await before.rawQuery('SELECT COUNT(*) FROM gl_entries'),
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
      expect(await db.getVersion(), 65);
      expect(DatabaseConstants.dbVersion, 65);
      final usersAfter = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM users'),
          ) ??
          0;
      final glAfter = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM gl_entries'),
          ) ??
          0;
      expect(usersAfter, usersBefore);
      expect(glAfter, glBefore);

      final org = await db.query(
        'organization_identity',
        columns: ['organization_id'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      expect(org.single['organization_id'], organizationId);

      final table = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='license_activation_state'",
      );
      expect(table.length, 1);
      final activationRows = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM license_activation_state'),
          ) ??
          -1;
      expect(activationRows, 0,
          reason: 'SEC.006 migration must not fabricate an online activation.');

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first.toString(), 'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      // ignore: avoid_print
      print('SEC006_DB_VERSION=${await db.getVersion()}');
      // ignore: avoid_print
      print('SEC006_ORGANIZATION_ID=$organizationId');
      // ignore: avoid_print
      print('SEC006_USERS_PRESERVED=$usersAfter');
      // ignore: avoid_print
      print('SEC006_GL_ENTRIES_PRESERVED=$glAfter');
      // ignore: avoid_print
      print('SEC006_ACTIVATION_ROWS=$activationRows');
      // ignore: avoid_print
      print('SEC006_INTEGRITY=ok');
      // ignore: avoid_print
      print('SEC006_FOREIGN_KEYS=ok');
    } finally {
      await db.close();
    }
  });
}
