import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test(
    'SEC.001 migrates the real database from v62 to v63 without identity loss',
    () async {
      final path = Platform.environment['YALLA_SEC001_LIVE_DB_PATH']?.trim();
      if (path == null || path.isEmpty) {
        throw StateError('YALLA_SEC001_LIVE_DB_PATH is required.');
      }

      final file = File(path);
      expect(file.existsSync(), isTrue, reason: path);

      final beforeDb = await sq.openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );

      late final List<Map<String, Object?>> beforeUsers;
      late final List<Map<String, Object?>> beforeWorkshop;
      try {
        final beforeVersion = sq.Sqflite.firstIntValue(
              await beforeDb.rawQuery('PRAGMA user_version'),
            ) ??
            0;
        expect(beforeVersion, 62);

        beforeUsers = await beforeDb.query(
          'users',
          columns: [
            'id',
            'name',
            'email',
            'password',
            'role',
            'status',
            'is_owner',
          ],
          orderBy: 'id',
        );
        beforeWorkshop = await beforeDb.query(
          'workshop_settings',
          columns: [
            'id',
            'workshopName',
            'country_code',
            'base_currency_code',
          ],
          orderBy: 'id',
        );
      } finally {
        await beforeDb.close();
      }

      final db = await DatabaseMigration.initDatabase(pathOverride: path);
      try {
        final afterVersion = sq.Sqflite.firstIntValue(
              await db.rawQuery('PRAGMA user_version'),
            ) ??
            0;
        expect(afterVersion, 63);

        final identityRows = await db.query(
          'organization_identity',
          where: 'singleton_id = 1',
        );
        expect(identityRows.length, 1);
        final organizationId =
            identityRows.single['organization_id']?.toString();
        expect(organizationId, isNotNull);
        expect(organizationId, isNotEmpty);

        final afterUsers = await db.query(
          'users',
          columns: [
            'id',
            'name',
            'email',
            'password',
            'role',
            'status',
            'is_owner',
          ],
          orderBy: 'id',
        );
        final afterWorkshop = await db.query(
          'workshop_settings',
          columns: [
            'id',
            'workshopName',
            'country_code',
            'base_currency_code',
          ],
          orderBy: 'id',
        );
        expect(
          afterUsers,
          beforeUsers,
          reason: 'User IDs/passwords must be preserved.',
        );
        expect(
          afterWorkshop,
          beforeWorkshop,
          reason: 'Workshop data must be preserved.',
        );

        final unscopedUsers = sq.Sqflite.firstIntValue(
              await db.rawQuery(
                "SELECT COUNT(*) FROM users WHERE organization_id IS NULL OR TRIM(organization_id) = ''",
              ),
            ) ??
            -1;
        final unscopedWorkshop = sq.Sqflite.firstIntValue(
              await db.rawQuery(
                "SELECT COUNT(*) FROM workshop_settings WHERE organization_id IS NULL OR TRIM(organization_id) = ''",
              ),
            ) ??
            -1;
        expect(unscopedUsers, 0);
        expect(unscopedWorkshop, 0);

        final integrity = await db.rawQuery('PRAGMA integrity_check');
        expect(integrity.first.values.first.toString(), 'ok');
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

        // ignore: avoid_print
        print('SEC001_DB_VERSION=$afterVersion');
        // ignore: avoid_print
        print('SEC001_ORGANIZATION_ID=$organizationId');
        // ignore: avoid_print
        print('SEC001_INTEGRITY=ok');
        // ignore: avoid_print
        print('SEC001_FOREIGN_KEYS=ok');
        // ignore: avoid_print
        print('SEC001_USERS_PRESERVED=${afterUsers.length}');
      } finally {
        await db.close();
      }
    },
  );
}
