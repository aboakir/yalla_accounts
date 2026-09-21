import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/insurance_commercial_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real v84 fixture migrates to v85 without losing business data',
      () async {
    final fixture = Platform.environment['YALLA_V84_FIXTURE'];
    if (fixture == null || fixture.trim().isEmpty) {
      return;
    }
    final source = File(fixture);
    expect(await source.exists(), isTrue);

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp =
        await Directory.systemTemp.createTemp('insurance_v84_upgrade_');
    final working = '${temp.path}/upgrade.db';
    await source.copy(working);

    final beforeDb = await databaseFactoryFfi.openDatabase(working);
    final beforeVersion = await beforeDb.getVersion();
    final before = <String, int>{};
    for (final table in const [
      'clients',
      'suppliers',
      'insurance_policies',
      'gl_entries',
      'payments',
      'cheques',
    ]) {
      before[table] = ((await beforeDb.rawQuery(
        'SELECT COUNT(*) n FROM $table',
      ))
              .single['n'] as num)
          .toInt();
    }
    await beforeDb.close();
    expect(beforeVersion, 84);

    final db = await DatabaseMigration.initDatabase(pathOverride: working);
    try {
      expect(await db.getVersion(), 85);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );

      for (final table in const [
        'clients',
        'insurance_policies',
        'gl_entries',
        'payments',
        'cheques',
      ]) {
        final after = ((await db.rawQuery(
          'SELECT COUNT(*) n FROM $table',
        ))
                .single['n'] as num)
            .toInt();
        expect(after, before[table], reason: 'row count changed for $table');
      }

      final companies = await db.query('insurance_companies');
      expect(companies, isNotEmpty);
      expect(
        companies.every(
          (row) =>
              row['party_id'] != null &&
              row['supplier_id'] != null &&
              (row['code'] ?? '').toString().trim().isNotEmpty,
        ),
        isTrue,
      );
      final companyRoles = ((await db.rawQuery(
        "SELECT COUNT(*) n FROM party_roles WHERE role='INSURANCE_COMPANY'",
      ))
              .single['n'] as num)
          .toInt();
      expect(companyRoles, companies.length);

      final preservedSupplierCount = before['suppliers'] ?? 0;
      final supplierCountAfter = ((await db.rawQuery(
        'SELECT COUNT(*) n FROM suppliers',
      ))
              .single['n'] as num)
          .toInt();
      expect(supplierCountAfter, greaterThanOrEqualTo(preservedSupplierCount));

      final companyCount = companies.length;
      final supplierCount = supplierCountAfter;
      final roleCount = ((await db.rawQuery(
        'SELECT COUNT(*) n FROM party_roles',
      ))
              .single['n'] as num)
          .toInt();

      await InsuranceCommercialTables.ensure(db);
      await PartyTables.ensure(db);
      await InsuranceCommercialTables.backfillLegacyCompanyParties(db);

      expect(
        ((await db.rawQuery('SELECT COUNT(*) n FROM insurance_companies'))
                .single['n'] as num)
            .toInt(),
        companyCount,
      );
      expect(
        ((await db.rawQuery('SELECT COUNT(*) n FROM suppliers')).single['n']
                as num)
            .toInt(),
        supplierCount,
      );
      expect(
        ((await db.rawQuery('SELECT COUNT(*) n FROM party_roles')).single['n']
                as num)
            .toInt(),
        roleCount,
      );
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
    } finally {
      if (db.isOpen) await db.close();
      await temp.delete(recursive: true);
    }
  });
}
