import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

String? _resolveLiveV55Fixture() {
  final configured = Platform.environment['YALLA_V55_FIXTURE_DB']?.trim();
  if (configured != null &&
      configured.isNotEmpty &&
      File(configured).existsSync()) {
    return configured;
  }

  if (!Platform.isWindows) return null;

  const candidates = <String>[
    r'D:\Yallah Accounts\yallah_accounts.db',
    r'D:\Yallah Accounts\yalla_accounts.db',
    r'D:\YallaAccounts\yallah_accounts.db',
    r'D:\YallaAccounts\yalla_accounts.db',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

Future<int> _count(Database db, String table) async {
  return Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $table'),
      ) ??
      0;
}

void main() {
  test('legacy migration orders organization scope before owner bootstrap', () {
    final source =
        File('lib/core/services/db/database_migration.dart').readAsStringSync();

    final organizationScope =
        source.indexOf('await OrganizationIdentityTables.ensure(db);');
    final ownerBootstrap =
        source.indexOf('await OwnerBootstrapTables.ensure(db);');

    expect(organizationScope, greaterThanOrEqualTo(0));
    expect(ownerBootstrap, greaterThan(organizationScope));
    expect(source, contains('VoucherTables.runTrustedPostedVoucherBackfill'));
  });

  final fixturePath = _resolveLiveV55Fixture();

  test(
    'live v55 copy migrates to current DB without losing business rows',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      DatabaseMigration.useDatabaseForTesting(null);

      final temp =
          await Directory.systemTemp.createTemp('yallah_live_v55_probe_');
      final dbPath = '${temp.path}/yallah_accounts.db';
      await File(fixturePath!).copy(dbPath);

      try {
        final baseline = await databaseFactoryFfi.openDatabase(dbPath);
        final beforeVersion = await baseline.getVersion();
        final repairsBefore = await _count(baseline, 'repairs');
        final vouchersBefore = await _count(baseline, 'vouchers');
        final glBefore = await _count(baseline, 'gl_entries');
        await baseline.close();

        if (beforeVersion != 55) {
          markTestSkipped(
            'Live fixture is v$beforeVersion; the destructive v55 probe only runs on v55.',
          );
          return;
        }

        final db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
        expect(await db.getVersion(), 78);
        expect(await _count(db, 'repairs'), repairsBefore);
        expect(await _count(db, 'vouchers'), vouchersBefore);
        expect(await _count(db, 'gl_entries'), glBefore);
        expect(
          (await db.rawQuery('PRAGMA integrity_check')).first.values.first,
          'ok',
        );
        final guards = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master "
          "WHERE type='trigger' "
          "AND name='trg_vouchers_posted_material_update'",
        ));
        expect(guards, 1);
        await db.close();
      } finally {
        DatabaseMigration.useDatabaseForTesting(null);
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
    skip: fixturePath == null
        ? 'No live v55 fixture is available on this CI runner.'
        : false,
  );
}
