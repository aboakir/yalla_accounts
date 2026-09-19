import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final realDb = Platform.environment['YALLAH_TRACK_B_REAL_DB'];

  test('B12 real-data copy migrates to current DB version', () async {
    final path = realDb!;
    expect(File(path).existsSync(), isTrue);

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      final rows = await db.rawQuery('PRAGMA user_version');
      final version = (rows.single['user_version'] as num).toInt();
      expect(version, DatabaseConstants.dbVersion);
    } finally {
      await db.close();
      DatabaseMigration.useDatabaseForTesting(null);
    }
  },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: realDb == null ? 'Requires YALLAH_TRACK_B_REAL_DB.' : false);
}
