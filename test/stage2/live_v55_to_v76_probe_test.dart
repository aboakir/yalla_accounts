import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  test('live v55 copy migrates to v76 without losing business rows', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseMigration.useDatabaseForTesting(null);

    final temp =
        await Directory.systemTemp.createTemp('yallah_live_v55_probe_');
    final dbPath = '${temp.path}/yalla_accounts.db';
    await File(r'D:\Yallah Accounts\yallah_accounts.db').copy(dbPath);

    try {
      final db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
      expect(await db.getVersion(), 76);
      expect(
          Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM repairs')),
          114);
      expect(
          Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM vouchers')),
          55);
      expect(
          Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM gl_entries')),
          344);
      expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first,
          'ok');
      final guards = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name='trg_vouchers_posted_material_update'",
      ));
      expect(guards, 1);
      await db.close();
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}
