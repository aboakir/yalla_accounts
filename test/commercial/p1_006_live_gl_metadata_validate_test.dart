import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

double number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

void main() {
  test('P1.006 live v60 to v61 preserves GL money and adds metadata', () async {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;

    final path = await DatabaseConstants.dbFilePath();
    expect(File(path).existsSync(), isTrue);

    final before = await databaseFactoryFfi.openDatabase(path);

    final versionBefore =
        firstInt(await before.rawQuery('PRAGMA user_version'));
    expect(versionBefore, 60);

    final totalsBefore = (await before.rawQuery(r'''
      SELECT COUNT(*) AS line_count,
             COALESCE(SUM(debit),0) AS debit_total,
             COALESCE(SUM(credit),0) AS credit_total
      FROM gl_lines
    ''')).single;

    final entriesBefore =
        firstInt(await before.rawQuery('SELECT COUNT(*) FROM gl_entries'));
    final nullCreatedAtBefore = firstInt(await before.rawQuery(
      "SELECT COUNT(*) FROM gl_entries "
      "WHERE created_at IS NULL OR TRIM(created_at)=''",
    ));

    await before.close();

    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      expect(firstInt(await db.rawQuery('PRAGMA user_version')), 61);

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first.toString(), 'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      final totalsAfter = (await db.rawQuery(r'''
        SELECT COUNT(*) AS line_count,
               COALESCE(SUM(debit),0) AS debit_total,
               COALESCE(SUM(credit),0) AS credit_total
        FROM gl_lines
      ''')).single;

      final entriesAfter =
          firstInt(await db.rawQuery('SELECT COUNT(*) FROM gl_entries'));

      expect(entriesAfter, entriesBefore);
      expect(
        (totalsAfter['line_count'] as num).toInt(),
        (totalsBefore['line_count'] as num).toInt(),
      );
      expect(
        number(totalsAfter['debit_total']),
        closeTo(number(totalsBefore['debit_total']), 0.0001),
      );
      expect(
        number(totalsAfter['credit_total']),
        closeTo(number(totalsBefore['credit_total']), 0.0001),
      );

      final metadataColumns =
          await db.rawQuery('PRAGMA table_info(gl_entries)');
      final names = metadataColumns.map((r) => r['name'].toString()).toSet();
      expect(names.contains('source_number'), isTrue);
      expect(names.contains('posting_version'), isTrue);
      expect(names.contains('reversal_of'), isTrue);
      expect(names.contains('created_by'), isTrue);

      expect(
        firstInt(await db.rawQuery(
          'SELECT COUNT(*) FROM gl_entries '
          'WHERE posting_version IS NULL OR posting_version < 1',
        )),
        0,
      );

      final reversalLinks = firstInt(await db.rawQuery(
        'SELECT COUNT(*) FROM gl_entries WHERE reversal_of IS NOT NULL',
      ));
      expect(reversalLinks, 77);

      final invalidReversalLinks = firstInt(await db.rawQuery(r'''
        SELECT COUNT(*)
        FROM gl_entries child
        LEFT JOIN gl_entries parent ON parent.id=child.reversal_of
        WHERE child.reversal_of IS NOT NULL
          AND (parent.id IS NULL OR child.id=child.reversal_of)
      '''));
      expect(invalidReversalLinks, 0);

      final voucherNumbers = firstInt(await db.rawQuery(r'''
        SELECT COUNT(*)
        FROM gl_entries g
        JOIN vouchers v ON v.id=g.source_id
        WHERE g.source='VOUCHER'
          AND g.source_number=v.voucher_number
          AND g.source_number IS NOT NULL
      '''));
      expect(voucherNumbers, 55);

      final nullCreatedAtAfter = firstInt(await db.rawQuery(
        "SELECT COUNT(*) FROM gl_entries "
        "WHERE created_at IS NULL OR TRIM(created_at)=''",
      ));
      expect(nullCreatedAtAfter, nullCreatedAtBefore);

      final unbalanced = firstInt(await db.rawQuery(r'''
        SELECT COUNT(*) FROM (
          SELECT e.id
          FROM gl_entries e
          JOIN gl_lines l ON l.entry_id=e.id
          GROUP BY e.id
          HAVING ABS(COALESCE(SUM(l.debit),0)
                   - COALESCE(SUM(l.credit),0)) > 0.01
        )
      '''));
      expect(unbalanced, 0);

      final duplicates = firstInt(await db.rawQuery(r'''
        SELECT COUNT(*) FROM (
          SELECT source, source_id
          FROM gl_entries
          GROUP BY source, source_id
          HAVING COUNT(*) > 1
        )
      '''));
      expect(duplicates, 0);

      await expectLater(
        db.update(
          'gl_entries',
          {'note': 'must fail'},
          where: 'id=?',
          whereArgs: [1],
        ),
        throwsA(anything),
      );

      print('P1.006 live GL metadata validation PASS.');
      print('Database version 61: PASS');
      print('Historical GL entries unchanged: $entriesAfter');
      print('Historical GL lines unchanged: ${totalsAfter['line_count']}');
      print('Debit total unchanged: ${totalsAfter['debit_total']}');
      print('Credit total unchanged: ${totalsAfter['credit_total']}');
      print('Deterministic reversal links: $reversalLinks');
      print('Voucher human source numbers linked: $voucherNumbers');
      print('Historical unknown created_at preserved: $nullCreatedAtAfter');
      print('Unbalanced entries: $unbalanced');
      print('Duplicate posting identities: $duplicates');
    } finally {
      await db.close();
    }
  });
}
