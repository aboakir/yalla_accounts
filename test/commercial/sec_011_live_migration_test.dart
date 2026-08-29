import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';

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

  test('SEC.011 upgrades live client DB to v68 without rewriting history',
      () async {
    final path = Platform.environment['YALLA_SEC011_LIVE_DB_PATH'];
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);

    final beforeDb = await databaseFactoryFfi.openDatabase(path);
    final usersBefore =
        firstInt(await beforeDb.rawQuery('SELECT COUNT(*) FROM users'));
    final glBefore =
        firstInt(await beforeDb.rawQuery('SELECT COUNT(*) FROM gl_entries'));
    await beforeDb.close();

    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      final version = firstInt(await db.rawQuery('PRAGMA user_version'));
      final integrity = (await db.rawQuery('PRAGMA integrity_check'))
          .first
          .values
          .first
          .toString();
      final fk = await db.rawQuery('PRAGMA foreign_key_check');
      final users = firstInt(await db.rawQuery('SELECT COUNT(*) FROM users'));
      final gl = firstInt(await db.rawQuery('SELECT COUNT(*) FROM gl_entries'));
      final runtimeRows = await db.query(LicenseRuntimeTables.table, limit: 2);
      final triggerCount = firstInt(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master "
        "WHERE type='trigger' AND name LIKE 'yalla_sec011_ro_%'",
      ));

      expect(version, greaterThanOrEqualTo(68));
      expect(integrity, 'ok');
      expect(fk, isEmpty);
      expect(users, usersBefore);
      expect(gl, glBefore);
      expect(runtimeRows.length, 1);
      expect(triggerCount, greaterThan(10));

      stdout.writeln('SEC011_DB_VERSION=$version');
      stdout.writeln('SEC011_USERS_PRESERVED=$users');
      stdout.writeln('SEC011_GL_ENTRIES_PRESERVED=$gl');
      stdout.writeln(
        'SEC011_RUNTIME_MODE=${runtimeRows.single['mode']}',
      );
      stdout.writeln('SEC011_READ_ONLY_TRIGGERS=$triggerCount');
      stdout.writeln('SEC011_INTEGRITY=$integrity');
      stdout.writeln('SEC011_FOREIGN_KEYS=ok');
    } finally {
      await db.close();
    }
  });
}
