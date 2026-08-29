import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

String _accountIdentity(Map<String, Object?> row) => [
      row['id'],
      row['code'],
      row['name'],
      row['type'],
    ].join('|');

String _glLineIdentity(Map<String, Object?> row) => [
      row['id'],
      row['entry_id'],
      row['account_id'],
      _double(row['debit']).toStringAsFixed(6),
      _double(row['credit']).toStringAsFixed(6),
    ].join('|');

void main() {
  test('P1.007 live v61 to v62 hardens COA without financial rewrite',
      () async {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;

    final path = await DatabaseConstants.dbFilePath();
    expect(File(path).existsSync(), isTrue);

    final before = await databaseFactoryFfi.openDatabase(path);

    final versionBefore =
        _int((await before.rawQuery('PRAGMA user_version')).first.values.first);
    expect(versionBefore, 61);

    final accountsBefore = await before.query(
      'accounts',
      columns: ['id', 'code', 'name', 'type', 'normal_balance'],
      orderBy: 'id',
    );
    final accountIdentityBefore =
        accountsBefore.map(_accountIdentity).toList(growable: false);

    final linesBefore = await before.query(
      'gl_lines',
      columns: ['id', 'entry_id', 'account_id', 'debit', 'credit'],
      orderBy: 'id',
    );
    final lineIdentityBefore =
        linesBefore.map(_glLineIdentity).toList(growable: false);

    final totalsBefore = (await before.rawQuery(r'''
      SELECT COUNT(*) AS line_count,
             COALESCE(SUM(debit),0) AS debit_total,
             COALESCE(SUM(credit),0) AS credit_total
      FROM gl_lines
    ''')).single;

    final entriesBefore = _int(
        (await before.rawQuery('SELECT COUNT(*) FROM gl_entries'))
            .first
            .values
            .first);

    final nullNormalBefore = _int((await before.rawQuery(
      "SELECT COUNT(*) FROM accounts "
      "WHERE normal_balance IS NULL OR TRIM(normal_balance)=''",
    ))
        .first
        .values
        .first);
    expect(nullNormalBefore, 13);

    await before.close();

    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      expect(DatabaseConstants.dbVersion, 62);
      expect(
        _int((await db.rawQuery('PRAGMA user_version')).first.values.first),
        62,
      );

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first.toString(), 'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      final accountsAfter = await db.query(
        'accounts',
        columns: ['id', 'code', 'name', 'type', 'normal_balance'],
        orderBy: 'id',
      );
      expect(accountsAfter.length, 96);
      expect(
        accountsAfter.map(_accountIdentity).toList(growable: false),
        accountIdentityBefore,
        reason: 'Account ids/codes/names/types must not be rewritten.',
      );

      final linesAfter = await db.query(
        'gl_lines',
        columns: ['id', 'entry_id', 'account_id', 'debit', 'credit'],
        orderBy: 'id',
      );
      expect(
        linesAfter.map(_glLineIdentity).toList(growable: false),
        lineIdentityBefore,
        reason: 'Historical GL account_id/debit/credit must be identical.',
      );

      final totalsAfter = (await db.rawQuery(r'''
        SELECT COUNT(*) AS line_count,
               COALESCE(SUM(debit),0) AS debit_total,
               COALESCE(SUM(credit),0) AS credit_total
        FROM gl_lines
      ''')).single;

      expect(
        _int(totalsAfter['line_count']),
        _int(totalsBefore['line_count']),
      );
      expect(
        _double(totalsAfter['debit_total']),
        closeTo(_double(totalsBefore['debit_total']), 0.0001),
      );
      expect(
        _double(totalsAfter['credit_total']),
        closeTo(_double(totalsBefore['credit_total']), 0.0001),
      );

      final entriesAfter = _int(
          (await db.rawQuery('SELECT COUNT(*) FROM gl_entries'))
              .first
              .values
              .first);
      expect(entriesAfter, entriesBefore);
      expect(entriesAfter, 445);
      expect(_int(totalsAfter['line_count']), 1040);

      final columns = await db.rawQuery('PRAGMA table_info(accounts)');
      final columnNames = columns.map((r) => r['name'].toString()).toSet();
      for (final required in [
        'report_class',
        'parent_id',
        'is_postable',
        'is_system',
        'is_active',
        'is_legacy',
      ]) {
        expect(columnNames.contains(required), isTrue);
      }

      expect(
        _int((await db.rawQuery(
          "SELECT COUNT(*) FROM accounts "
          "WHERE normal_balance IS NULL OR TRIM(normal_balance)=''",
        ))
            .first
            .values
            .first),
        0,
      );
      expect(
        _int((await db.rawQuery(
          "SELECT COUNT(*) FROM accounts "
          "WHERE report_class IS NULL OR TRIM(report_class)=''",
        ))
            .first
            .values
            .first),
        0,
      );

      // All historical account codes remain unique/nonblank.
      expect(
        _int((await db.rawQuery(r'''
          SELECT COUNT(*) FROM (
            SELECT code FROM accounts
            GROUP BY code HAVING COUNT(*) > 1
          )
        ''')).first.values.first),
        0,
      );
      expect(
        _int((await db.rawQuery(
          "SELECT COUNT(*) FROM accounts "
          "WHERE code IS NULL OR TRIM(code)=''",
        ))
            .first
            .values
            .first),
        0,
      );

      // Expected hierarchy from the audited Case Zero.
      expect(
        _int((await db.rawQuery(r'''
          SELECT COUNT(*) FROM accounts
          WHERE code LIKE '1200.C%'
            AND parent_id=(SELECT id FROM accounts WHERE code='1200')
        ''')).first.values.first),
        26,
      );
      expect(
        _int((await db.rawQuery(r'''
          SELECT COUNT(*) FROM accounts
          WHERE code GLOB '2200.S[0-9]*'
            AND parent_id=(SELECT id FROM accounts WHERE code='2200')
        ''')).first.values.first),
        14,
      );
      expect(
        _int((await db.rawQuery(r'''
          SELECT COUNT(*) FROM accounts
          WHERE code LIKE '1200.E%'
            AND parent_id=(SELECT id FROM accounts WHERE code='1120')
            AND is_legacy=1 AND is_postable=0 AND is_active=1
        ''')).first.values.first),
        6,
      );
      expect(
        _int((await db.rawQuery(r'''
          SELECT COUNT(*) FROM accounts
          WHERE code LIKE '2000.S%'
            AND is_legacy=1 AND is_postable=0 AND is_active=0
        ''')).first.values.first),
        13,
      );
      expect(
        _int((await db.rawQuery(r'''
          SELECT COUNT(*) FROM accounts
          WHERE code LIKE '2200.SS%'
            AND is_legacy=1 AND is_postable=0 AND is_active=0
        ''')).first.values.first),
        13,
      );

      // Header roots are protected and non-postable.
      expect(
        _int((await db.rawQuery(r'''
          SELECT COUNT(*) FROM accounts
          WHERE code IN ('1120','1200','2140','2200')
            AND is_system=1 AND is_active=1 AND is_postable=0
        ''')).first.values.first),
        4,
      );

      expect(
        _int((await db.rawQuery(r'''
          SELECT COUNT(*)
          FROM accounts child
          LEFT JOIN accounts parent ON parent.id=child.parent_id
          WHERE child.parent_id IS NOT NULL AND parent.id IS NULL
        ''')).first.values.first),
        0,
      );

      final unbalanced = _int((await db.rawQuery(r'''
        SELECT COUNT(*) FROM (
          SELECT e.id
          FROM gl_entries e
          JOIN gl_lines l ON l.entry_id=e.id
          GROUP BY e.id
          HAVING ABS(COALESCE(SUM(l.debit),0)
                   - COALESCE(SUM(l.credit),0)) > 0.01
        )
      ''')).first.values.first);
      expect(unbalanced, 0);

      print('P1.007 live COA validation PASS.');
      print('Database version 62: PASS');
      print('Accounts preserved: ${accountsAfter.length}');
      print('Historical GL entries unchanged: $entriesAfter');
      print('Historical GL lines unchanged: ${totalsAfter['line_count']}');
      print('Debit unchanged: ${totalsAfter['debit_total']}');
      print('Credit unchanged: ${totalsAfter['credit_total']}');
      print('Legacy 1200.E employee advances preserved: 6');
      print('Retired legacy supplier aliases: 26');
      print('Canonical supplier accounts: 14');
      print('Client hierarchy accounts: 26');
      print('Unbalanced entries: $unbalanced');
    } finally {
      await db.close();
    }
  });
}
