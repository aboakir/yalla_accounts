import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test(
    'SEC.009 keeps live DB v67 unchanged and healthy',
    () async {
      final path = Platform.environment['YALLA_SEC009_LIVE_DB_PATH']?.trim();
      if (path == null || path.isEmpty) {
        throw StateError('YALLA_SEC009_LIVE_DB_PATH is required.');
      }

      final db = await sq.openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        expect(await db.getVersion(), 67);
        expect(DatabaseConstants.dbVersion, 67);
        expect((await db.query('auth_roles')).length, RoleKeys.all.length);
        expect(
          (await db.query('auth_permissions')).length,
          PermissionKeys.all.length,
        );

        final users = sq.Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM users'),
            ) ??
            0;
        final activeUsers = sq.Sqflite.firstIntValue(
              await db.rawQuery(
                "SELECT COUNT(*) FROM users WHERE status = 'active'",
              ),
            ) ??
            0;
        final glEntries = sq.Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM gl_entries'),
            ) ??
            0;

        expect(users, greaterThanOrEqualTo(1));
        expect(activeUsers, greaterThanOrEqualTo(1));
        expect(
          (await db.rawQuery('PRAGMA integrity_check')).first.values.first,
          'ok',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

        // ignore: avoid_print
        print('SEC009_DB_VERSION=${await db.getVersion()}');
        // ignore: avoid_print
        print('SEC009_USERS_PRESERVED=$users');
        // ignore: avoid_print
        print('SEC009_ACTIVE_USERS=$activeUsers');
        // ignore: avoid_print
        print('SEC009_ROLES=${(await db.query('auth_roles')).length}');
        // ignore: avoid_print
        print(
            'SEC009_PERMISSIONS=${(await db.query('auth_permissions')).length}');
        // ignore: avoid_print
        print('SEC009_GL_ENTRIES_PRESERVED=$glEntries');
        // ignore: avoid_print
        print('SEC009_INTEGRITY=ok');
        // ignore: avoid_print
        print('SEC009_FOREIGN_KEYS=ok');
      } finally {
        await db.close();
      }
    },
    skip: (Platform.environment['YALLA_SEC009_LIVE_DB_PATH']?.trim().isEmpty ??
            true)
        ? 'Historical fixture test; set YALLA_SEC009_LIVE_DB_PATH explicitly to run'
        : false,
  );
}
