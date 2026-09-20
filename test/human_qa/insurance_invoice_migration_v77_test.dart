import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v76 to v77 installs canonical insurance invoices schema', () async {
    final dir = await Directory.systemTemp.createTemp('insurance_v77_');
    final path = '${dir.path}/fixture.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      await db.execute('DROP TABLE insurance_invoices');
      await db.delete(
        'schema_migrations',
        where: 'version = ?',
        whereArgs: [77],
      );
      await db.setVersion(76);
      await db.close();

      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), DatabaseConstants.dbVersion);

      final info = await db.rawQuery('PRAGMA table_info(insurance_invoices)');
      final columns = info.map((row) => row['name']).toSet();
      expect(
        columns,
        containsAll(<String>{
          'id',
          'invoice_number',
          'client_name',
          'insurance_company',
          'amount',
          'date',
          'status',
        }),
      );

      final id = await db.insert('insurance_invoices', <String, Object?>{
        'invoice_number': 'INS-001',
        'client_name': 'Test Client',
        'insurance_company': 'Test Insurance',
        'amount': 500.0,
        'date': DateTime(2026, 9, 19).toIso8601String(),
        'status': 'معلق',
      });
      expect(id, greaterThan(0));
      expect(await db.query('insurance_invoices'), hasLength(1));
      expect(
        await db.query('schema_migrations', where: 'version = 77'),
        hasLength(1),
      );
    } finally {
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });
}
