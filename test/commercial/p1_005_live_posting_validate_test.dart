import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';

double number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

void main() {
  test('P1.005 live Case Zero remains balanced and intact', () async {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;

    final path = await DatabaseConstants.dbFilePath();
    expect(File(path).existsSync(), isTrue);

    final db = await databaseFactoryFfi.openDatabase(path);
    try {
      final version = sq.Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      expect(version, 60);

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first.toString(), 'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      final totals = (await db.rawQuery(r'''
        SELECT COUNT(*) AS line_count,
               COALESCE(SUM(debit),0) AS debit_total,
               COALESCE(SUM(credit),0) AS credit_total
        FROM gl_lines
      ''')).first;

      final debit = number(totals['debit_total']);
      final credit = number(totals['credit_total']);
      expect(debit, closeTo(credit, 0.0001));

      final unbalanced = sq.Sqflite.firstIntValue(await db.rawQuery(r'''
        SELECT COUNT(*) FROM (
          SELECT e.id
          FROM gl_entries e
          LEFT JOIN gl_lines l ON l.entry_id=e.id
          GROUP BY e.id
          HAVING ABS(COALESCE(SUM(l.debit),0)-COALESCE(SUM(l.credit),0)) > 0.01
        )
      ''')) ?? 0;
      expect(unbalanced, 0);

      final duplicates = sq.Sqflite.firstIntValue(await db.rawQuery(r'''
        SELECT COUNT(*) FROM (
          SELECT source, source_id
          FROM gl_entries
          GROUP BY source, source_id
          HAVING COUNT(*) > 1
        )
      ''')) ?? 0;
      expect(duplicates, 0);

      final orphans = sq.Sqflite.firstIntValue(await db.rawQuery(r'''
        SELECT COUNT(*)
        FROM gl_lines l
        LEFT JOIN gl_entries e ON e.id=l.entry_id
        WHERE e.id IS NULL
      ''')) ?? 0;
      expect(orphans, 0);

      print('P1.005 live validation PASS.');
      print('Database version 60: PASS');
      print('Debit total: $debit');
      print('Credit total: $credit');
      print('Unbalanced entries: $unbalanced');
      print('Duplicate posting identities: $duplicates');
      print('Orphan GL lines: $orphans');
    } finally {
      await db.close();
    }
  });
}
