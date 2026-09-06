import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';

double n(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

void main() {
  test(
    'P1.004 live DB remains v60 and financially unchanged',
    () async {
      sqfliteFfiInit();
      sq.databaseFactory = databaseFactoryFfi;

      final path = Platform.environment['YALLA_P1004_LIVE_DB_PATH']!.trim();
      expect(File(path).existsSync(), isTrue);

      final db = await databaseFactoryFfi.openDatabase(path);
      try {
        expect(firstInt(await db.rawQuery('PRAGMA user_version')), 60);
        expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first,
            'ok');
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

        final gl = await db.rawQuery(
          'SELECT COUNT(*) c, COALESCE(SUM(debit),0) d, '
          'COALESCE(SUM(credit),0) cr FROM gl_lines',
        );

        final debit = n(gl.first['d']);
        final credit = n(gl.first['cr']);
        expect((debit - credit).abs(), lessThan(0.0001));

        final settings = await db.query(
          'workshop_settings',
          columns: [
            'base_currency_code',
            'currency_symbol',
            'currency_decimals',
          ],
          where: 'id=1',
          limit: 1,
        );
        expect(settings, isNotEmpty);
        expect(settings.first['base_currency_code'], 'ILS');
        expect(settings.first['currency_symbol'], '₪');
        expect((settings.first['currency_decimals'] as num).toInt(), 2);

        print('P1.004 live presentation validation PASS.');
        print('Database version 60: PASS');
        print('GL balanced: PASS');
        print('Foreign-key validation: PASS');
        print('DB integrity: PASS');
        print('Live base currency ILS / 2 decimals: PASS');
      } finally {
        await db.close();
      }
    },
    skip: (Platform.environment['YALLA_P1004_LIVE_DB_PATH']?.trim().isEmpty ??
            true)
        ? 'Requires audited v60 fixture; default suite must not touch customer DB'
        : false,
  );
}
