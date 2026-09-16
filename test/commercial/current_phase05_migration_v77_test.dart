import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'v76 to v77 installs unified sync queues without resetting business data',
    () async {
      final dir = await Directory.systemTemp.createTemp('phase05_v77_');
      final path = '${dir.path}/fixture.db';
      var db = await DatabaseMigration.initDatabase(pathOverride: path);

      try {
        expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(77));
        expect(await db.getVersion(), DatabaseConstants.dbVersion);
        await db.insert('suppliers', {'name': 'Preserved Supplier'});
        final before = await db.query(
          'suppliers',
          where: 'name=?',
          whereArgs: ['Preserved Supplier'],
        );

        await db.delete(
          'schema_migrations',
          where: 'version=?',
          whereArgs: [77],
        );
        await db.execute('DROP TRIGGER IF EXISTS trg_sync_v3_change_to_outbox');
        await db.execute('DROP TABLE ${UnifiedSyncTables.inbox}');
        await db.execute('DROP TABLE ${UnifiedSyncTables.checkpoint}');
        await db.execute('DROP TABLE ${UnifiedSyncTables.outbox}');
        await db.setVersion(76);
        await db.close();

        db = await DatabaseMigration.initDatabase(pathOverride: path);
        expect(await db.getVersion(), DatabaseConstants.dbVersion);
        expect(
          await db.query(
            'schema_migrations',
            where: 'version=?',
            whereArgs: [77],
          ),
          hasLength(1),
        );
        expect(
          await db.query(
            'suppliers',
            where: 'name=?',
            whereArgs: ['Preserved Supplier'],
          ),
          before,
        );
        for (final table in [
          UnifiedSyncTables.outbox,
          UnifiedSyncTables.inbox,
          UnifiedSyncTables.checkpoint,
        ]) {
          expect(
            await db.rawQuery(
              "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
              [table],
            ),
            isNotEmpty,
          );
        }
      } finally {
        if (db.isOpen) await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
