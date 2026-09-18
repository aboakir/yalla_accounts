import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v75 to v76 installs raw materials and restores write guards', () async {
    final dir = await Directory.systemTemp.createTemp('raw_material_v76_');
    final path = '${dir.path}/fixture.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      expect(DatabaseConstants.dbVersion, 76);
      expect(await db.getVersion(), 76);

      await db.delete(
        'schema_migrations',
        where: 'version = ?',
        whereArgs: [76],
      );
      await db.execute('DROP TABLE raw_materials');
      await db.setVersion(75);
      await db.close();

      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), 76);

      final columns = await db.rawQuery('PRAGMA table_info(raw_materials)');
      expect(
        columns.map((row) => row['name']).toSet(),
        containsAll(<String>{
          'id',
          'name',
          'supplier',
          'quantity',
          'unit_price',
          'description',
        }),
      );

      final indexes = await db.rawQuery('PRAGMA index_list(raw_materials)');
      expect(
        indexes.map((row) => row['name']).toSet(),
        containsAll(<String>{
          'idx_raw_materials_name',
          'idx_raw_materials_supplier',
        }),
      );

      await db.insert('raw_materials', <String, Object?>{
        'name': 'Primer',
        'supplier': 'Supplier A',
        'quantity': 3,
        'unit_price': 42.5,
      });
      expect((await db.query('raw_materials')).single['name'], 'Primer');
      expect(
        await db.query('schema_migrations', where: 'version = 76'),
        hasLength(1),
      );

      await db.update(
        'license_runtime_state',
        <String, Object?>{
          'mode': 'READ_ONLY_EXPIRED',
          'reason': 'phase8 regression test',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'singleton_id = 1',
      );

      await expectLater(
        db.insert('raw_materials', <String, Object?>{
          'name': 'Blocked paint',
          'supplier': 'Supplier B',
          'quantity': 1,
          'unit_price': 10.0,
        }),
        throwsA(
            predicate((error) => error.toString().contains('YALLA_READ_ONLY'))),
      );
    } finally {
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });
}
