import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('SEC.008 migrates live DB v66 to v67 without credential rewrites',
      () async {
    final path = Platform.environment['YALLA_SEC008_LIVE_DB_PATH']?.trim();
    if (path == null || path.isEmpty) {
      throw StateError('YALLA_SEC008_LIVE_DB_PATH is required.');
    }

    final before = await sq.openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );
    late List<Map<String, Object?>> usersBefore;
    late int glBefore;
    try {
      expect(await before.getVersion(), 66);
      usersBefore = (await before.query(
        'users',
        columns: ['id', 'password', 'is_owner', 'organization_id'],
        orderBy: 'id',
      ))
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      glBefore = sq.Sqflite.firstIntValue(
            await before.rawQuery('SELECT COUNT(*) FROM gl_entries'),
          ) ??
          0;
    } finally {
      await before.close();
    }

    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      expect(await db.getVersion(), 67);
      expect(DatabaseConstants.dbVersion, 67);

      final usersAfter = (await db.query(
        'users',
        columns: ['id', 'password', 'is_owner', 'organization_id'],
        orderBy: 'id',
      ))
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      expect(usersAfter, usersBefore);

      final owner = (await db.query(
        'users',
        columns: ['role'],
        where: 'is_owner = 1',
      ));
      if (owner.isNotEmpty) {
        expect(owner.single['role'], RoleKeys.owner);
      }

      expect((await db.query('auth_roles')).length, RoleKeys.all.length);
      expect(
        (await db.query('auth_permissions')).length,
        PermissionKeys.all.length,
      );

      final glAfter = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM gl_entries'),
          ) ??
          0;
      expect(glAfter, glBefore);
      expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first,
          'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      // ignore: avoid_print
      print('SEC008_DB_VERSION=${await db.getVersion()}');
      // ignore: avoid_print
      print('SEC008_USERS_PRESERVED=${usersAfter.length}');
      // ignore: avoid_print
      print('SEC008_ROLES=${(await db.query('auth_roles')).length}');
      // ignore: avoid_print
      print(
          'SEC008_PERMISSIONS=${(await db.query('auth_permissions')).length}');
      // ignore: avoid_print
      print('SEC008_GL_ENTRIES_PRESERVED=$glAfter');
      // ignore: avoid_print
      print('SEC008_INTEGRITY=ok');
      // ignore: avoid_print
      print('SEC008_FOREIGN_KEYS=ok');
    } finally {
      await db.close();
    }
  });
}
