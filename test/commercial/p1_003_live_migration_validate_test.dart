import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

double n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int i(List<Map<String, Object?>> rows) {
  final v = rows.first.values.first;
  return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}

void main() {
  test(
    'P1.003 live v59 to v60 preserves history',
    () async {
      sqfliteFfiInit();
      sq.databaseFactory = databaseFactoryFfi;
      final path = Platform.environment['YALLA_P1003_LIVE_DB_PATH']!.trim();
      expect(File(path).existsSync(), isTrue);

      final before = await databaseFactoryFfi.openDatabase(path);
      final glBefore = await before.rawQuery(
        'SELECT COUNT(*) c, COALESCE(SUM(debit),0) d, '
        'COALESCE(SUM(credit),0) cr FROM gl_lines',
      );
      final invBefore = n((await before.rawQuery(
        'SELECT COALESCE(SUM(total),0) s FROM invoices',
      ))
          .first['s']);
      await before.close();

      final db = await DatabaseMigration.initDatabase(pathOverride: path);
      try {
        expect(
          i(await db.rawQuery('PRAGMA user_version')),
          DatabaseConstants.dbVersion,
        );
        expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first,
            'ok');
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

        final glAfter = await db.rawQuery(
          'SELECT COUNT(*) c, COALESCE(SUM(debit),0) d, '
          'COALESCE(SUM(credit),0) cr FROM gl_lines',
        );
        expect(i(glAfter), i(glBefore));
        expect(n(glAfter.first['d']), closeTo(n(glBefore.first['d']), 0.0001));
        expect(
            n(glAfter.first['cr']), closeTo(n(glBefore.first['cr']), 0.0001));

        final invAfter = n((await db.rawQuery(
          'SELECT COALESCE(SUM(total),0) s FROM invoices',
        ))
            .first['s']);
        expect(invAfter, closeTo(invBefore, 0.0001));

        expect(
            i(await db.rawQuery(
              "SELECT COUNT(*) FROM invoices WHERE currency_code='ILS'",
            )),
            113);

        final seq = await db.query(
          'document_sequences',
          where: 'document_type=?',
          whereArgs: ['PAYMENT_VOUCHER'],
          limit: 1,
        );
        expect((seq.first['next_value'] as num).toInt(), 56);

        print('P1.003 live migration validation PASS.');
        print('Database upgraded to current version: PASS');
        print('Historical GL unchanged: PASS');
        print('Historical invoice totals unchanged: PASS');
        print('Historical ILS facts preserved: PASS');
        print('Next payment voucher sequence P-0056: PASS');
      } finally {
        await db.close();
      }
    },
    skip: (Platform.environment['YALLA_P1003_LIVE_DB_PATH']?.trim().isEmpty ??
            true)
        ? 'Requires audited v59 fixture; default suite must not touch customer DB'
        : false,
  );
}
