import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbPath = r'D:/YallaAccounts/yalla_accounts.db';
const _fixSource = 'P0_REPAIR_FIX';

const _expectedLegacyEntryIds = <int>{
  2,
  3,
  24,
  25,
  28,
  29,
  46,
  47,
  85,
  86,
  89,
  90,
  129,
  130,
  173,
  174,
  189,
  190,
  204,
  205,
  223,
  224,
  225,
  226,
  243,
  244,
  245,
  246,
  249,
  250,
  251,
  252,
  253,
  254,
  255,
  256,
  257,
  258,
  259,
  260,
  261,
  262,
  263,
  264,
  284,
  285,
  286,
  287,
  288,
  291,
  292,
  293,
  294,
  309,
  310,
  313,
  314,
  315,
  316,
  323,
  324,
  330,
  331,
  332,
  333,
  336,
  337,
  338,
  339,
  343,
  344
};

const _expectedLegacyEntries = 71;
const _expectedLegacyLines = 212;
const _expectedLegacyDebit = 338660.00;
const _expectedLegacyCredit = 338660.00;
const _expectedMissingInvoiceId = 'db2a8a09-a868-40f4-bfe4-36f3732953b2';

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

int _firstIntValue(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Future<void> _writeReport(String name, Map<String, Object?> body) async {
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile == null || userProfile.isEmpty) return;

  final file = File(
    '$userProfile${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}$name',
  );

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(body),
    flush: true,
  );
}

Future<List<Map<String, Object?>>> _legacyEntries(Database db) {
  return db.query(
    'gl_entries',
    where: "source IN ('REPAIR_REV','REPAIR_ADJ')",
    orderBy: 'id ASC',
  );
}

Future<void> _validateLegacySnapshot(
  Database db,
  List<Map<String, Object?>> entries,
) async {
  final ids = entries.map((e) => _int(e['id'])).toSet();

  if (entries.length != _expectedLegacyEntries ||
      ids.length != _expectedLegacyEntryIds.length ||
      !ids.containsAll(_expectedLegacyEntryIds) ||
      !_expectedLegacyEntryIds.containsAll(ids)) {
    throw StateError(
      'P0.002 refused: legacy REPAIR_REV/REPAIR_ADJ entry set changed. '
      'Found=${entries.length}.',
    );
  }

  final totals = await db.rawQuery(r'''
    SELECT
      COUNT(l.id) AS line_count,
      COALESCE(SUM(l.debit),0) AS debit_total,
      COALESCE(SUM(l.credit),0) AS credit_total
    FROM gl_entries e
    JOIN gl_lines l ON l.entry_id=e.id
    WHERE e.source IN ('REPAIR_REV','REPAIR_ADJ')
  ''');

  final row = totals.first;
  final lineCount = _int(row['line_count']);
  final debit = _number(row['debit_total']);
  final credit = _number(row['credit_total']);

  if (lineCount != _expectedLegacyLines ||
      (debit - _expectedLegacyDebit).abs() > 0.01 ||
      (credit - _expectedLegacyCredit).abs() > 0.01) {
    throw StateError(
      'P0.002 refused: legacy repair GL totals changed. '
      'lines=$lineCount debit=$debit credit=$credit',
    );
  }

  final badLegacy = _firstIntValue(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT e.id, SUM(l.debit-l.credit) AS diff
        FROM gl_entries e
        JOIN gl_lines l ON l.entry_id=e.id
        WHERE e.source IN ('REPAIR_REV','REPAIR_ADJ')
        GROUP BY e.id
        HAVING ABS(diff) > 0.01
      )
    '''),
  );

  if (badLegacy != 0) {
    throw StateError(
      'P0.002 refused: one or more legacy repair GL entries are unbalanced.',
    );
  }
}

Future<void> _validateP0001(Database db) async {
  final rows = await db.rawQuery(r'''
    SELECT COUNT(*) AS c
    FROM gl_entries
    WHERE source='P0_DUP_REV'
  ''');

  if (_int(rows.first['c']) != 4) {
    throw StateError(
      'P0.002 refused: expected four P0.001 duplicate-posting reversals.',
    );
  }
}

Future<Map<String, Object?>> _postValidation(Database db) async {
  final fixEntries = _firstIntValue(
    await db.rawQuery(
      "SELECT COUNT(*) FROM gl_entries WHERE source=?",
      [_fixSource],
    ),
  );

  final fixLines = _firstIntValue(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      WHERE e.source=?
    ''', [_fixSource]),
  );

  final nonZeroRepairNet = _firstIntValue(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT l.repair_id, SUM(l.debit-l.credit) AS diff
        FROM gl_entries e
        JOIN gl_lines l ON l.entry_id=e.id
        WHERE e.source IN ('REPAIR_REV','REPAIR_ADJ','P0_REPAIR_FIX')
        GROUP BY l.repair_id
        HAVING ABS(diff) > 0.01
      )
    '''),
  );

  final nonZeroAccountNet = _firstIntValue(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT l.account_id, SUM(l.debit-l.credit) AS diff
        FROM gl_entries e
        JOIN gl_lines l ON l.entry_id=e.id
        WHERE e.source IN ('REPAIR_REV','REPAIR_ADJ','P0_REPAIR_FIX')
        GROUP BY l.account_id
        HAVING ABS(diff) > 0.01
      )
    '''),
  );

  final unbalancedGl = _firstIntValue(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT entry_id, SUM(debit-credit) AS diff
        FROM gl_lines
        GROUP BY entry_id
        HAVING ABS(diff) > 0.01
      )
    '''),
  );

  final invoiceMismatches = await db.rawQuery(r'''
    WITH inv_effect AS (
      SELECT
        i.id AS invoice_id,
        i.total AS invoice_total,
        i.repair_id,
        COALESCE(
          SUM(
            CASE WHEN a.code='4000'
            THEN l.credit-l.debit ELSE 0 END
          ),
          0
        ) AS revenue_effect,
        COUNT(
          DISTINCT CASE WHEN e.source='INVOICE' THEN e.id END
        ) AS invoice_entries,
        COUNT(
          DISTINCT CASE WHEN e.source='INVOICE_REV' THEN e.id END
        ) AS invoice_reversals
      FROM invoices i
      LEFT JOIN gl_entries e
        ON (e.source='INVOICE' AND e.source_id=i.id)
        OR (e.source='P0_DUP_REV' AND e.source_id=i.id)
        OR (e.source='INVOICE_REV' AND e.source_id=i.id || '_REV')
        OR (
          e.source IN ('REPAIR_REV','REPAIR_ADJ')
          AND e.source_id=i.repair_id
        )
        OR (
          e.source='P0_REPAIR_FIX'
          AND EXISTS (
            SELECT 1
            FROM gl_lines fx
            WHERE fx.entry_id=e.id
              AND fx.repair_id=i.repair_id
          )
        )
      LEFT JOIN gl_lines l ON l.entry_id=e.id
      LEFT JOIN accounts a ON a.id=l.account_id
      GROUP BY i.id
    )
    SELECT
      invoice_id,
      invoice_total,
      revenue_effect,
      invoice_entries,
      invoice_reversals
    FROM inv_effect
    WHERE ABS(
      revenue_effect -
      CASE WHEN invoice_reversals > 0 THEN 0 ELSE invoice_total END
    ) > 0.01
    ORDER BY invoice_id
  ''');

  final integrity = await db.rawQuery('PRAGMA integrity_check');
  final integrityOk =
      integrity.isNotEmpty && integrity.first.values.first.toString() == 'ok';

  final expectedOnlyMissingInvoice = invoiceMismatches.length == 1 &&
      invoiceMismatches.first['invoice_id']?.toString() ==
          _expectedMissingInvoiceId &&
      _int(invoiceMismatches.first['invoice_entries']) == 0;

  return {
    'fix_entries': fixEntries,
    'fix_lines': fixLines,
    'non_zero_repair_net': nonZeroRepairNet,
    'non_zero_account_net': nonZeroAccountNet,
    'unbalanced_gl_entries': unbalancedGl,
    'invoice_mismatch_count': invoiceMismatches.length,
    'invoice_mismatches': invoiceMismatches,
    'expected_only_missing_invoice': expectedOnlyMissingInvoice,
    'integrity_ok': integrityOk,
  };
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(_dbPath).existsSync()) {
    stderr.writeln('P0.002 ERROR: database not found at $_dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(_dbPath);

  try {
    final version = _firstIntValue(await db.rawQuery('PRAGMA user_version'));

    if (version != 55) {
      throw StateError(
        'P0.002 refused: expected DB user_version 55, found $version.',
      );
    }

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first.toString() != 'ok') {
      throw StateError('P0.002 refused: DB integrity_check is not OK.');
    }

    await _validateP0001(db);

    final legacy = await _legacyEntries(db);
    await _validateLegacySnapshot(db, legacy);

    final existingFixes = await db.query(
      'gl_entries',
      columns: ['source_id'],
      where: 'source=?',
      whereArgs: [_fixSource],
    );

    if (existingFixes.isNotEmpty) {
      final fixedIds = existingFixes
          .map((e) => int.tryParse(e['source_id']?.toString() ?? ''))
          .whereType<int>()
          .toSet();

      if (fixedIds.length == _expectedLegacyEntryIds.length &&
          fixedIds.containsAll(_expectedLegacyEntryIds) &&
          _expectedLegacyEntryIds.containsAll(fixedIds)) {
        final validation = await _postValidation(db);

        if (validation['fix_entries'] != _expectedLegacyEntries ||
            validation['fix_lines'] != _expectedLegacyLines ||
            validation['non_zero_repair_net'] != 0 ||
            validation['non_zero_account_net'] != 0 ||
            validation['unbalanced_gl_entries'] != 0 ||
            validation['expected_only_missing_invoice'] != true ||
            validation['integrity_ok'] != true) {
          throw StateError(
            'P0.002 previous repair exists but validation failed: '
            '$validation',
          );
        }

        stdout.writeln(
          'P0.002 DATA REPAIR: already applied and validated. '
          'No new DB rows written.',
        );
        return;
      }

      throw StateError(
        'P0.002 refused: partial/unexpected P0_REPAIR_FIX entries exist.',
      );
    }

    stdout.writeln(
      'P0.002 preflight PASS: '
      '71 legacy repair GL headers / 212 lines identified.',
    );
    stdout.writeln(
      'Legacy REPAIR_REV + REPAIR_ADJ gross debit/credit: '
      '338,660.00 ILS each.',
    );

    if (!apply) {
      stdout.writeln('Audit only. Re-run with --apply to write reversals.');
      return;
    }

    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final entry in legacy) {
        final originalId = _int(entry['id']);
        final originalSource = entry['source']?.toString() ?? '';

        final lines = await txn.query(
          'gl_lines',
          where: 'entry_id=?',
          whereArgs: [originalId],
          orderBy: 'id ASC',
        );

        final fixEntryId = await txn.insert(
          'gl_entries',
          {
            'date': now,
            'ref': 'P0.002-$originalSource-$originalId',
            'source': _fixSource,
            'source_id': originalId.toString(),
            'note': 'P0.002 neutralizes legacy $originalSource GL entry '
                '#$originalId without deleting or editing it.',
            'created_at': now,
            'updated_at': now,
          },
        );

        for (final line in lines) {
          await txn.insert(
            'gl_lines',
            {
              'entry_id': fixEntryId,
              'account_id': line['account_id'],
              'debit': _number(line['credit']),
              'credit': _number(line['debit']),
              'party_type': line['party_type'],
              'party_id': line['party_id'],
              'invoice_id': line['invoice_id'],
              'repair_id': line['repair_id'],
              'cheque_id': line['cheque_id'],
              'reference_id': originalId.toString(),
              'reference_type': 'P0_REPAIR_FIX',
              'created_at': now,
            },
          );
        }
      }
    });

    final validation = await _postValidation(db);

    if (validation['fix_entries'] != _expectedLegacyEntries ||
        validation['fix_lines'] != _expectedLegacyLines ||
        validation['non_zero_repair_net'] != 0 ||
        validation['non_zero_account_net'] != 0 ||
        validation['unbalanced_gl_entries'] != 0 ||
        validation['expected_only_missing_invoice'] != true ||
        validation['integrity_ok'] != true) {
      throw StateError(
        'P0.002 post-repair validation failed: $validation',
      );
    }

    await _writeReport(
      'Yalla_P0_002_DATA_REPAIR_RESULT.json',
      {
        'status': 'PASS',
        'timestamp': now,
        'legacy_entries_neutralized': _expectedLegacyEntries,
        'legacy_lines_neutralized': _expectedLegacyLines,
        'legacy_gross_debit_ils': _expectedLegacyDebit,
        'legacy_gross_credit_ils': _expectedLegacyCredit,
        'net_effect_of_legacy_plus_fix': 0,
        'unbalanced_gl_entries': 0,
        'remaining_invoice_accounting_mismatches': 1,
        'remaining_expected_missing_invoice_id': _expectedMissingInvoiceId,
        'integrity_check': 'ok',
      },
    );

    stdout.writeln(
      'P0.002 DATA REPAIR PASS: 71 immutable neutralizing entries created.',
    );
    stdout.writeln(
      'P0.002 historical REPAIR_REV / REPAIR_ADJ net effect: 0.00 ILS.',
    );
    stdout.writeln('P0.002 GL validation PASS: all GL entries balanced.');
    stdout.writeln(
      'P0.002 invoice accounting validation PASS: '
      'only the audited missing 2,200 ILS invoice remains for P0.004.',
    );
    stdout.writeln('P0.002 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
