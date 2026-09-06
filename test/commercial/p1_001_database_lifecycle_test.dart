import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('P1.001 fresh install creates the current structurally valid DB',
      () async {
    final temp = await Directory.systemTemp.createTemp(
      'yalla_p1_001_fresh_',
    );
    final path = '${temp.path}${Platform.pathSeparator}fresh.db';

    final db = await DatabaseMigration.initDatabase(
      pathOverride: path,
    );

    try {
      final version = sq.Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      expect(version, DatabaseConstants.dbVersion);

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first.toString(), 'ok');

      final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
      expect(foreignKeys, isEmpty);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();

      for (final required in DatabaseConstants.coreTables) {
        expect(names.contains(required), isTrue, reason: required);
      }

      final glCount = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM gl_entries'),
          ) ??
          -1;
      expect(glCount, 0);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.001 prior-version upgrade is idempotent on current schema',
      () async {
    final temp = await Directory.systemTemp.createTemp(
      'yalla_p1_001_upgrade_',
    );
    final path = '${temp.path}${Platform.pathSeparator}upgrade.db';

    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    await db.execute('PRAGMA user_version = 57');
    await db.close();

    db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      final version = sq.Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      expect(version, DatabaseConstants.dbVersion);

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first.toString(), 'ok');

      final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
      expect(foreignKeys, isEmpty);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.001 no alternate SQLite opener survives in compatibility paths', () {
    final provider = source('lib/core/database/database_provider.dart');
    final legacyPayments = source(
      'lib/features/payments/services/payment_database_service.dart',
    );
    final legacyRepairPath = source(
      'lib/features/repairs/services/payment_database_service.dart',
    );

    expect(provider.contains('openDatabase('), isFalse);
    expect(provider.contains('DBService.database'), isTrue);

    // The source comment intentionally documents the old `payments.db`
    // defect. Test executable DB-opening primitives instead of raw filename
    // text so documentation cannot trigger a false positive.
    expect(legacyPayments.contains('openDatabase('), isFalse);
    expect(legacyPayments.contains('getDatabasesPath('), isFalse);
    expect(legacyPayments.contains('databaseFactory.openDatabase'), isFalse);
    expect(legacyPayments.contains('DBService.database'), isTrue);

    expect(
      legacyRepairPath.contains("export 'repair_database_service.dart';"),
      isTrue,
    );
  });

  test('P1.001 backup never calls destructive database reset', () {
    final backup = source('lib/core/services/backup_service.dart');

    expect(backup.contains('resetDatabase('), isFalse);
    expect(backup.contains('closeDatabase(checkpoint: true)'), isTrue);
    expect(backup.contains('validateDatabaseCandidate'), isTrue);
    expect(backup.contains('safetyBackup'), isTrue);
  });

  test('P1.001 migration preserves legacy purchase detail', () {
    final migration = source(
      'lib/core/services/db/database_migration.dart',
    );

    expect(migration.contains('SET itemName = NULL'), isFalse);
    expect(
      migration.contains(
        'preserving legacy purchase detail columns unchanged',
      ),
      isTrue,
    );
  });

  test('P1.001 production UI has no Reset DB action', () {
    final settings = source(
      'lib/features/settings/screens/settings_screen.dart',
    );

    expect(settings.contains('"Reset DB"'), isFalse);
    expect(settings.contains('_resetDatabase'), isFalse);
  });

  test('P1.001 startup fails closed on DB bootstrap error', () {
    final mainSource = source('lib/main.dart');

    expect(mainSource.contains('_BootstrapFailureApp'), isTrue);
    expect(
      mainSource.contains(
        'لن يتم إنشاء قاعدة بديلة أو متابعة العمل على قاعدة غير سليمة',
      ),
      isTrue,
    );
  });
}
