import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('SEC.010 leaves live client DB v67 and accounting/auth data unchanged',
      () async {
    final path = Platform.environment['YALLA_SEC010_LIVE_DB_PATH'] ??
        await DatabaseConstants.dbFilePath();
    expect(File(path).existsSync(), isTrue);
    final db = await databaseFactoryFfi.openDatabase(path);
    try {
      final version = firstInt(await db.rawQuery('PRAGMA user_version'));
      final integrity = (await db.rawQuery('PRAGMA integrity_check'))
          .first
          .values
          .first
          .toString();
      final fk = await db.rawQuery('PRAGMA foreign_key_check');
      final users = firstInt(await db.rawQuery('SELECT COUNT(*) FROM users'));
      final roles =
          firstInt(await db.rawQuery('SELECT COUNT(*) FROM auth_roles'));
      final permissions =
          firstInt(await db.rawQuery('SELECT COUNT(*) FROM auth_permissions'));
      final gl = firstInt(await db.rawQuery('SELECT COUNT(*) FROM gl_entries'));
      expect(version, 67);
      expect(integrity, 'ok');
      expect(fk, isEmpty);
      expect(roles, 9);
      expect(permissions, 28);
      stdout.writeln('SEC010_DB_VERSION=$version');
      stdout.writeln('SEC010_USERS_PRESERVED=$users');
      stdout.writeln('SEC010_ROLES=$roles');
      stdout.writeln('SEC010_PERMISSIONS=$permissions');
      stdout.writeln('SEC010_GL_ENTRIES_PRESERVED=$gl');
      stdout.writeln('SEC010_INTEGRITY=$integrity');
      stdout.writeln('SEC010_FOREIGN_KEYS=ok');
    } finally {
      await db.close();
    }
  });
}
