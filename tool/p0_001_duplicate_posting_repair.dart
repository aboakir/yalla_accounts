import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbPath = r'D:/YallaAccounts/yalla_accounts.db';
const _repairSource = 'P0_DUP_REV';

const _expectedInvoiceIds = <String>{
  'c8acdcd5-4efe-42f7-a8a3-a143295af0e2',
  '555f8082-8094-4438-a0e8-4b31837e26e1',
  'f40f5dfa-2dc5-4c87-bf3b-6ae3b6e9e9c7',
  'b5380967-854d-4862-9f51-fc84c41c1b8a',
};

int _firstIntValue(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

Future<List<Map<String, Object?>>> _findCandidates(Database db) async {
  final rows = await db.rawQuery(r'''
    SELECT
      e.id AS entry_id,
      i.id AS invoice_id,
      i.repair_id AS repair_id,
      i.client_id AS client_id,
      i.total AS invoice_total,
      COALESCE(i.vat_amount, 0) AS vat_amount,
      COALESCE(i.vat, 0) AS vat,
      SUM(
        CASE WHEN a.code LIKE '1200.C%'
        THEN l.debit - l.credit ELSE 0 END
      ) AS ar_effect,
      SUM(
        CASE WHEN a.code = '4000'
        THEN l.credit - l.debit ELSE 0 END
      ) AS revenue_effect,
      MAX(
        CASE WHEN a.code LIKE '1200.C%'
        THEN l.account_id ELSE NULL END
      ) AS ar_account_id,
      MAX(
        CASE WHEN a.code = '4000'
        THEN l.account_id ELSE NULL END
      ) AS revenue_account_id
    FROM gl_entries e
    JOIN invoices i
      ON i.id = e.source_id
    JOIN gl_lines l
      ON l.entry_id = e.id
    JOIN accounts a
      ON a.id = l.account_id
    WHERE e.source = 'INVOICE'
    GROUP BY e.id, i.id
    ORDER BY e.id
  ''');

  final result = <Map<String, Object?>>[];

  for (final row in rows) {
    final total = _number(row['invoice_total']);
    final ar = _number(row['ar_effect']);
    final revenue = _number(row['revenue_effect']);
    final vatAmount = _number(row['vat_amount']);
    final vat = _number(row['vat']);
    final extra = ar - total;

    if (extra <= 0.01) continue;

    if ((ar - revenue).abs() > 0.01) {
      throw StateError(
        'P0.001 refused: invoice ${row['invoice_id']} has '
        'non-matching AR/revenue effects.',
      );
    }

    if (vatAmount.abs() > 0.01 || vat.abs() > 0.01) {
      throw StateError(
        'P0.001 refused: VAT invoice ${row['invoice_id']} needs '
        'a separate audited repair path.',
      );
    }

    if (row['ar_account_id'] == null || row['revenue_account_id'] == null) {
      throw StateError(
        'P0.001 refused: required GL accounts are missing for '
        '${row['invoice_id']}.',
      );
    }

    result.add({...row, 'extra_amount': extra});
  }

  return result;
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

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(_dbPath).existsSync()) {
    stderr.writeln('P0.001 ERROR: database not found at $_dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(_dbPath);

  try {
    final version =
        _firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;

    if (version != 55) {
      throw StateError(
        'P0.001 refused: expected DB user_version 55, found $version.',
      );
    }

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first.toString() != 'ok') {
      throw StateError('P0.001 refused: DB integrity_check is not OK.');
    }

    final candidates = await _findCandidates(db);
    final candidateIds =
        candidates.map((e) => e['invoice_id'].toString()).toSet();
    final extraTotal = candidates.fold<double>(
      0,
      (sum, row) => sum + _number(row['extra_amount']),
    );

    final existingRepairRows = await db.query(
      'gl_entries',
      columns: ['source_id'],
      where: 'source = ?',
      whereArgs: [_repairSource],
    );
    final existingRepairIds =
        existingRepairRows.map((e) => e['source_id'].toString()).toSet();

    if (existingRepairIds.isNotEmpty) {
      if (existingRepairIds.length == _expectedInvoiceIds.length &&
          existingRepairIds.containsAll(_expectedInvoiceIds) &&
          _expectedInvoiceIds.containsAll(existingRepairIds)) {
        stdout.writeln(
          'P0.001 DATA REPAIR: already applied. No DB rows written.',
        );
        return;
      }
      throw StateError(
        'P0.001 refused: partial/unexpected prior repair entries exist: '
        '$existingRepairIds',
      );
    }

    if (candidateIds.length != 4 ||
        !candidateIds.containsAll(_expectedInvoiceIds) ||
        !_expectedInvoiceIds.containsAll(candidateIds) ||
        (extraTotal - 11000.0).abs() > 0.01) {
      await _writeReport(
        'Yalla_P0_001_PREFLIGHT_MISMATCH.json',
        {
          'status': 'REFUSED',
          'candidate_ids': candidateIds.toList(),
          'extra_total': extraTotal,
          'expected_ids': _expectedInvoiceIds.toList(),
          'expected_extra_total': 11000.0,
        },
      );

      throw StateError(
        'P0.001 refused: live DB no longer matches the audited snapshot. '
        'Candidates=${candidateIds.length}, extra=$extraTotal.',
      );
    }

    stdout.writeln(
      'P0.001 preflight PASS: 4 duplicate invoice postings; '
      'excess = 11000.00 ILS.',
    );

    if (!apply) {
      stdout.writeln('Audit only. Re-run with --apply to write reversals.');
      return;
    }

    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final row in candidates) {
        final invoiceId = row['invoice_id'].toString();
        final repairId = row['repair_id']?.toString();
        final clientId = _int(row['client_id']);
        final originalEntryId = _int(row['entry_id']);
        final arAccountId = _int(row['ar_account_id']);
        final revenueAccountId = _int(row['revenue_account_id']);
        final extra = _number(row['extra_amount']);

        final entryId = await txn.insert(
          'gl_entries',
          {
            'date': now,
            'ref': 'P0.001-DUP-$invoiceId',
            'source': _repairSource,
            'source_id': invoiceId,
            'note': 'P0.001 reversal of duplicate invoice posting. '
                'Original GL entry #$originalEntryId; '
                'reversed excess ${extra.toStringAsFixed(2)} ILS.',
            'created_at': now,
            'updated_at': now,
          },
        );

        await txn.insert(
          'gl_lines',
          {
            'entry_id': entryId,
            'account_id': arAccountId,
            'debit': 0.0,
            'credit': extra,
            'party_type': 'CLIENT',
            'party_id': clientId.toString(),
            'invoice_id': invoiceId,
            'repair_id': repairId,
            'reference_type': 'P0_DUP_REV',
            'reference_id': invoiceId,
            'created_at': now,
          },
        );

        await txn.insert(
          'gl_lines',
          {
            'entry_id': entryId,
            'account_id': revenueAccountId,
            'debit': extra,
            'credit': 0.0,
            'party_type': null,
            'party_id': null,
            'invoice_id': invoiceId,
            'repair_id': repairId,
            'reference_type': 'P0_DUP_REV',
            'reference_id': invoiceId,
            'created_at': now,
          },
        );
      }
    });

    final repaired = await db.query(
      'gl_entries',
      columns: ['source_id'],
      where: 'source = ?',
      whereArgs: [_repairSource],
    );

    final unbalanced = _firstIntValue(
          await db.rawQuery(r'''
            SELECT COUNT(*)
            FROM (
              SELECT entry_id, SUM(debit - credit) AS diff
              FROM gl_lines
              GROUP BY entry_id
              HAVING ABS(diff) > 0.01
            )
          '''),
        ) ??
        -1;

    final integrityAfter = await db.rawQuery('PRAGMA integrity_check');
    final integrityOk = integrityAfter.isNotEmpty &&
        integrityAfter.first.values.first.toString() == 'ok';

    if (repaired.length != 4 || unbalanced != 0 || !integrityOk) {
      throw StateError(
        'P0.001 post-repair validation failed: '
        'repair_entries=${repaired.length}, '
        'unbalanced=$unbalanced, integrity=$integrityOk',
      );
    }

    await _writeReport(
      'Yalla_P0_001_DATA_REPAIR_RESULT.json',
      {
        'status': 'PASS',
        'timestamp': now,
        'reversal_entries': repaired.length,
        'reversed_excess_ils': 11000.0,
        'invoice_ids': _expectedInvoiceIds.toList(),
        'unbalanced_gl_entries': unbalanced,
        'integrity_check': 'ok',
      },
    );

    stdout.writeln(
      'P0.001 DATA REPAIR PASS: 4 reversal entries created; '
      'reversed excess = 11000.00 ILS.',
    );
    stdout.writeln('P0.001 GL validation PASS: all GL entries balanced.');
    stdout.writeln('P0.001 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
