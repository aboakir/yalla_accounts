// Generates the bundled synthetic insurance-v84 migration fixture.
//
// IMPORTANT: this file must be executed against the historical DB84 release
// commit eef3d1b, not against the current checkout. The reproducible packaging
// procedure is documented in test/fixtures/migration/INSURANCE_V84.md.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

const _expectedCommercial83Sha256 =
    'bf51c18f01d7abb3480c59ef31813e8716412e83c4dc50f89b06e524835a7830';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('build provenance-bound synthetic insurance v84 fixture', () async {
    final sourcePath = Platform.environment['YALLA_COMMERCIAL83_FIXTURE'];
    final outputPath = Platform.environment['YALLA_INSURANCE84_OUTPUT'];
    expect(sourcePath, isNotNull,
        reason: 'YALLA_COMMERCIAL83_FIXTURE is required');
    expect(outputPath, isNotNull,
        reason: 'YALLA_INSURANCE84_OUTPUT is required');
    expect(DatabaseConstants.dbVersion, 84,
        reason: 'Run this builder only at DB84 release commit eef3d1b');

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    DatabaseMigration.useDatabaseForTesting(null);

    final sourceBytes = gzip.decode(await File(sourcePath!).readAsBytes());
    expect(sha256.convert(sourceBytes).toString(), _expectedCommercial83Sha256);

    final temp = await Directory.systemTemp.createTemp('insurance_v84_build_');
    final dbPath = '${temp.path}/insurance-v84.db';
    Database? db;
    try {
      await File(dbPath).writeAsBytes(sourceBytes, flush: true);
      db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
      expect(await db.getVersion(), 84);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      const timestamp = '2026-09-22T00:00:00.000Z';
      await db.insert('insurance_companies', {
        'id': 8401,
        'name': 'Synthetic V84 Insurance Company',
      });
      await db.insert('insurance_policies', {
        'id': 'synthetic-v84-policy',
        'created_at': timestamp,
        'updated_at': timestamp,
        'vehicle_plate': 'V84-TEST',
        'vehicle_make': 'Synthetic Vehicle',
        'vehicle_model_year': '2026',
        'engine_cc': '1600',
        'insured_name': 'Synthetic V84 Insured',
        'insured_phone': '0599000084',
        'company_name': 'Synthetic V84 Insurance Company',
        'start_date': '2026-09-22',
        'end_date': '2027-09-21',
        'is_vip': 0,
        'buy_price': 800.0,
        'sell_price': 1000.0,
        'payment_type': 'installments',
        'cash_amount': 0.0,
        'notes': 'Synthetic legacy v84 migration sentinel',
      });
      await db.insert('insurance_policy_installments', {
        'id': 'synthetic-v84-installment',
        'policy_id': 'synthetic-v84-policy',
        'amount': 1000.0,
        'due_date': '2026-10-22',
        'note': 'Must remain a schedule without premature GL',
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('PRAGMA journal_mode=DELETE');
      await db.close();
      db = null;

      final builtBytes = await File(dbPath).readAsBytes();
      expect(builtBytes.sublist(18, 20), [1, 1],
          reason: 'Fixture must be a standalone rollback-journal database');
      await File(outputPath!)
          .writeAsBytes(gzip.encode(builtBytes), flush: true);
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db != null && db.isOpen) await db.close();
      await temp.delete(recursive: true);
    }
  });
}
