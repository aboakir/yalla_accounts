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

  test('SEC.007 migrates live DB v65 to v66 without credential rewrites',
      () async {
    final path = Platform.environment['YALLA_SEC007_LIVE_DB_PATH']?.trim();
    if (path == null || path.isEmpty) {
      throw StateError('YALLA_SEC007_LIVE_DB_PATH is required.');
    }
    final before =
        await sq.openDatabase(path, readOnly: true, singleInstance: false);
    late List<Map<String, Object?>> usersBefore;
    late int glBefore;
    late String organizationId;
    try {
      expect(await before.getVersion(), 65);
      usersBefore = (await before.query('users',
              columns: ['id', 'password', 'is_owner', 'organization_id'],
              orderBy: 'id'))
          .map((e) => Map<String, Object?>.from(e))
          .toList();
      glBefore = sq.Sqflite.firstIntValue(
              await before.rawQuery('SELECT COUNT(*) FROM gl_entries')) ??
          0;
      organizationId = (await before.query('organization_identity',
              columns: ['organization_id'], where: 'singleton_id=1'))
          .single['organization_id']!
          .toString();
    } finally {
      await before.close();
    }

    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      expect(await db.getVersion(), 66);
      expect(DatabaseConstants.dbVersion, 66);
      final usersAfter = (await db.query('users',
              columns: ['id', 'password', 'is_owner', 'organization_id'],
              orderBy: 'id'))
          .map((e) => Map<String, Object?>.from(e))
          .toList();
      expect(usersAfter, usersBefore);
      final glAfter = sq.Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM gl_entries')) ??
          0;
      expect(glAfter, glBefore);
      final state = (await db.query('owner_bootstrap_state')).single;
      expect(state['organization_id'], organizationId);
      if (usersAfter.isEmpty) {
        expect(state['status'], 'PENDING');
      } else {
        final owners = usersAfter.where((e) => e['is_owner'] == 1).toList();
        expect(owners.length, 1);
        expect(state['status'], 'COMPLETED');
        expect(state['owner_user_id'], owners.single['id']);
      }
      expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first,
          'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      // ignore: avoid_print
      print('SEC007_DB_VERSION=${await db.getVersion()}');
      // ignore: avoid_print
      print('SEC007_ORGANIZATION_ID=$organizationId');
      // ignore: avoid_print
      print('SEC007_USERS_PRESERVED=${usersAfter.length}');
      // ignore: avoid_print
      print("SEC007_BOOTSTRAP_STATUS=${state['status']}");
      // ignore: avoid_print
      print('SEC007_GL_ENTRIES_PRESERVED=$glAfter');
      // ignore: avoid_print
      print('SEC007_INTEGRITY=ok');
      // ignore: avoid_print
      print('SEC007_FOREIGN_KEYS=ok');
    } finally {
      await db.close();
    }
  });
}
