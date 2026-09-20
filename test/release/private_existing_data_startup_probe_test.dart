import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sourceDirectory =
      Platform.environment['YALLAH_PRIVATE_STARTUP_SNAPSHOTS'];
  for (final name in ['legacy55', 'desktop77']) {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.windows]) {
      test(
          'private read-only snapshot $name opens under ${platform.name} policy',
          () async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        SharedPreferences.setMockInitialValues({});
        debugDefaultTargetPlatformOverride = platform;
        final directory =
            await Directory.systemTemp.createTemp('yallah_startup_probe_');
        final target = '${directory.path}/copy.db';
        await File('$sourceDirectory/$name.db').copy(target);
        Database? db;
        try {
          db = await DatabaseMigration.initDatabase(pathOverride: target);
          DatabaseMigration.useDatabaseForTesting(db);
          expect(await db.getVersion(), DatabaseConstants.dbVersion);
          expect(
              (await db.rawQuery('PRAGMA integrity_check'))
                  .single
                  .values
                  .single,
              'ok');
          await AccountingTables.ensureDefaultAccounts(db);
          await CommercialSettingsService.instance.get();
          await db.close();
          DatabaseMigration.useDatabaseForTesting(null);
          db = await DatabaseMigration.initDatabase(pathOverride: target);
          expect(await db.getVersion(), DatabaseConstants.dbVersion);
        } finally {
          DatabaseMigration.useDatabaseForTesting(null);
          if (db != null && db.isOpen) await db.close();
          debugDefaultTargetPlatformOverride = null;
          await directory.delete(recursive: true);
        }
      },
          skip: sourceDirectory == null
              ? 'Private local snapshot is intentionally not bundled.'
              : false,
          timeout: const Timeout(Duration(minutes: 3)));
    }
  }
}
