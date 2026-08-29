import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbPath = r'D:/YallaAccounts/yalla_accounts.db';
const _fixSource = 'P0_AP_RECLASS';

const _expectedEntryIds = <int>{
  7,
  20,
  31,
  35,
  45,
  49,
  71,
  74,
  77,
  81,
  105,
  107,
  117,
  122,
  123,
  179,
  183,
  209,
  216,
  233,
  270,
  273,
  274,
  280,
};

const _expectedWrongPaymentTotal = 34382.98;
const _expectedFinalApTotal = 41434.00;

const _expectedSupplierBalances = <int, double>{
  1: 0.00,
  2: 2140.00,
  3: 0.00,
  4: 8500.00,
  5: 0.00,
  6: 0.00,
  7: 0.00,
  8: 0.00,
  9: 0.00,
  10: 28793.00,
  11: 0.00,
  12: 4000.00,
  13: -1999.00,
  14: 0.00,
};

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int _firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  return _int(rows.first.values.first);
}

Future<void> _writeReport(Map<String, Object?> body) async {
  final home = Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return;

  final file = File(
    '$home${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}Yalla_P0_005_SUPPLIER_AP_RESULT.json',
  );

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(body),
    flush: true,
  );
}

Future<List<Map<String, Object?>>> _wrongLines(Database db) {
  return db.rawQuery(r'''
    SELECT
      e.id AS entry_id,
      e.source,
      e.source_id AS voucher_id,
      e.date,
      l.id AS line_id,
      l.account_id AS wrong_account_id,
      a.code AS wrong_code,
      l.debit,
      l.credit,
      l.party_type,
      l.party_id,
      l.invoice_id,
      ca.id AS canonical_account_id,
      ca.code AS canonical_code
    FROM gl_lines l
    JOIN gl_entries e ON e.id=l.entry_id
    JOIN accounts a ON a.id=l.account_id
    JOIN accounts ca
      ON ca.code='2200.S' || printf('%04d', CAST(l.party_id AS INTEGER))
    WHERE a.code GLOB '2000.S[0-9]*'
    ORDER BY e.id
  ''');
}

Future<void> _validateBaseline(
  Database db,
  List<Map<String, Object?>> rows,
) async {
  if (rows.length != _expectedEntryIds.length) {
    throw StateError(
      'P0.005 refused: expected 24 legacy supplier-payment lines, '
      'found ${rows.length}.',
    );
  }

  final foundIds = <int>{};
  var total = 0.0;

  for (final row in rows) {
    final entryId = _int(row['entry_id']);
    final supplierId = _int(row['party_id']);
    final wrongCode = row['wrong_code']?.toString() ?? '';
    final canonicalCode = row['canonical_code']?.toString() ?? '';
    final debit = _number(row['debit']);
    final credit = _number(row['credit']);

    foundIds.add(entryId);
    total += debit - credit;

    if (row['source']?.toString() != 'VOUCHER' ||
        row['party_type']?.toString().toUpperCase() != 'SUPPLIER' ||
        supplierId <= 0 ||
        wrongCode != '2000.S$supplierId' ||
        canonicalCode != '2200.S${supplierId.toString().padLeft(4, '0')}' ||
        debit <= 0.0 ||
        credit.abs() > 0.01) {
      throw StateError(
        'P0.005 refused: unexpected legacy supplier line: $row',
      );
    }
  }

  if (foundIds.length != _expectedEntryIds.length ||
      !foundIds.containsAll(_expectedEntryIds) ||
      !_expectedEntryIds.containsAll(foundIds) ||
      (total - _expectedWrongPaymentTotal).abs() > 0.01) {
    throw StateError(
      'P0.005 refused: live DB no longer matches audited AP baseline. '
      'ids=$foundIds total=$total',
    );
  }

  final purchaseCredit = _number(
    (await db.rawQuery(r'''
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS v
      FROM gl_lines l
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code GLOB '2200.S[0-9][0-9][0-9][0-9]'
    ''')).first['v'],
  );

  if ((purchaseCredit - 75816.98).abs() > 0.01) {
    throw StateError(
      'P0.005 refused: canonical supplier AP baseline changed. '
      'Found $purchaseCredit instead of 75816.98.',
    );
  }
}

Future<Map<String, Object?>> _validateAfter(Database db) async {
  final fixEntries = _firstInt(
    await db.rawQuery(
      'SELECT COUNT(*) FROM gl_entries WHERE source=?',
      [_fixSource],
    ),
  );

  final fixLines = _firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      WHERE e.source=?
    ''', [_fixSource]),
  );

  final fixTotals = await db.rawQuery(r'''
    SELECT
      COALESCE(SUM(l.debit),0) AS debit,
      COALESCE(SUM(l.credit),0) AS credit
    FROM gl_lines l
    JOIN gl_entries e ON e.id=l.entry_id
    WHERE e.source=?
  ''', [_fixSource]);

  final fixDebit = _number(fixTotals.first['debit']);
  final fixCredit = _number(fixTotals.first['credit']);

  final wrongNet = _number(
    (await db.rawQuery(r'''
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS v
      FROM gl_lines l
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code GLOB '2000.S[0-9]*'
    ''')).first['v'],
  );

  final canonicalNet = _number(
    (await db.rawQuery(r'''
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS v
      FROM gl_lines l
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code GLOB '2200.S[0-9][0-9][0-9][0-9]'
    ''')).first['v'],
  );

  final supplierRows = await db.rawQuery(r'''
    SELECT
      s.id AS supplier_id,
      COALESCE(SUM(l.credit-l.debit),0) AS balance
    FROM suppliers s
    LEFT JOIN accounts a
      ON a.code='2200.S' || printf('%04d',s.id)
    LEFT JOIN gl_lines l ON l.account_id=a.id
    GROUP BY s.id
    ORDER BY s.id
  ''');

  final supplierBalances = <String, double>{};

  for (final row in supplierRows) {
    final id = _int(row['supplier_id']);
    final value = _number(row['balance']);
    supplierBalances[id.toString()] = value;

    final expected = _expectedSupplierBalances[id];
    if (expected == null || (value - expected).abs() > 0.01) {
      throw StateError(
        'P0.005 supplier $id AP mismatch: expected $expected, found $value.',
      );
    }
  }

  final unbalanced = _firstInt(
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

  final integrity = await db.rawQuery('PRAGMA integrity_check');
  final integrityOk =
      integrity.isNotEmpty && integrity.first.values.first.toString() == 'ok';

  return {
    'fix_entries': fixEntries,
    'fix_lines': fixLines,
    'fix_debit': fixDebit,
    'fix_credit': fixCredit,
    'legacy_2000_net_after': wrongNet,
    'canonical_2200_net_after': canonicalNet,
    'supplier_balances': supplierBalances,
    'unbalanced_gl_entries': unbalanced,
    'integrity_ok': integrityOk,
  };
}

bool _afterIsValid(Map<String, Object?> after) {
  return after['fix_entries'] == 24 &&
      after['fix_lines'] == 48 &&
      (((after['fix_debit'] as double) - _expectedWrongPaymentTotal).abs() <=
          0.01) &&
      (((after['fix_credit'] as double) - _expectedWrongPaymentTotal).abs() <=
          0.01) &&
      ((after['legacy_2000_net_after'] as double).abs() <= 0.01) &&
      (((after['canonical_2200_net_after'] as double) - _expectedFinalApTotal)
              .abs() <=
          0.01) &&
      after['unbalanced_gl_entries'] == 0 &&
      after['integrity_ok'] == true;
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(_dbPath).existsSync()) {
    stderr.writeln('P0.005 ERROR: DB not found at $_dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(_dbPath);

  try {
    final version = _firstInt(await db.rawQuery('PRAGMA user_version'));
    if (version != 55) {
      throw StateError(
        'P0.005 refused: expected DB user_version 55, found $version.',
      );
    }

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first.toString() != 'ok') {
      throw StateError('P0.005 refused: DB integrity_check is not OK.');
    }

    final wrong = await _wrongLines(db);
    await _validateBaseline(db, wrong);

    final existing = await db.query(
      'gl_entries',
      columns: ['source_id'],
      where: 'source=?',
      whereArgs: [_fixSource],
    );

    if (existing.isNotEmpty) {
      final ids = existing
          .map((e) => int.tryParse(e['source_id']?.toString() ?? ''))
          .whereType<int>()
          .toSet();

      if (ids.length == _expectedEntryIds.length &&
          ids.containsAll(_expectedEntryIds) &&
          _expectedEntryIds.containsAll(ids)) {
        final after = await _validateAfter(db);

        if (!_afterIsValid(after)) {
          throw StateError(
            'P0.005 previous repair exists but validation failed: $after',
          );
        }

        stdout.writeln(
          'P0.005 DATA REPAIR: already applied and fully validated.',
        );
        return;
      }

      throw StateError(
        'P0.005 refused: partial/unexpected P0_AP_RECLASS entries exist.',
      );
    }

    stdout.writeln(
      'P0.005 preflight PASS: 24 supplier-payment GL lines are split '
      'into legacy 2000.S* accounts.',
    );
    stdout.writeln(
      'Audited supplier-payment reclassification total: 34,382.98 ILS.',
    );

    if (!apply) {
      stdout.writeln('Audit only. Re-run with --apply to reclassify.');
      return;
    }

    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final row in wrong) {
        final originalEntryId = _int(row['entry_id']);
        final supplierId = _int(row['party_id']);
        final wrongAccountId = _int(row['wrong_account_id']);
        final canonicalAccountId = _int(row['canonical_account_id']);
        final amount = _number(row['debit']) - _number(row['credit']);
        final originalDate = row['date']?.toString() ?? now;
        final voucherId = row['voucher_id']?.toString();
        final invoiceId = row['invoice_id']?.toString();

        final fixEntryId = await txn.insert(
          'gl_entries',
          {
            'date': originalDate,
            'ref': voucherId,
            'source': _fixSource,
            'source_id': originalEntryId.toString(),
            'note': 'P0.005 reclassifies supplier payment from legacy 2000.S* '
                'to canonical 2200.S####. Original GL #$originalEntryId.',
            'created_at': now,
            'updated_at': now,
          },
        );

        await txn.insert(
          'gl_lines',
          {
            'entry_id': fixEntryId,
            'account_id': wrongAccountId,
            'debit': 0.0,
            'credit': amount,
            'party_type': 'SUPPLIER',
            'party_id': supplierId.toString(),
            'invoice_id': invoiceId,
            'repair_id': null,
            'reference_id': originalEntryId.toString(),
            'reference_type': _fixSource,
            'created_at': now,
          },
        );

        await txn.insert(
          'gl_lines',
          {
            'entry_id': fixEntryId,
            'account_id': canonicalAccountId,
            'debit': amount,
            'credit': 0.0,
            'party_type': 'SUPPLIER',
            'party_id': supplierId.toString(),
            'invoice_id': invoiceId,
            'repair_id': null,
            'reference_id': originalEntryId.toString(),
            'reference_type': _fixSource,
            'created_at': now,
          },
        );
      }
    });

    final after = await _validateAfter(db);

    if (!_afterIsValid(after)) {
      throw StateError(
        'P0.005 post-repair validation failed: $after',
      );
    }

    await _writeReport({
      'status': 'PASS',
      'historical_reclass_entries': 24,
      'historical_reclass_lines': 48,
      'reclassified_supplier_payments_ils': _expectedWrongPaymentTotal,
      'legacy_2000_supplier_net_after': 0.0,
      'canonical_2200_supplier_ap_net_ils': _expectedFinalApTotal,
      'supplier_balances': after['supplier_balances'],
      'supplier_13_note':
          'Supplier 13 has a 1,999.00 ILS debit balance after reclassification; '
              'this is preserved as an overpayment/advance, not silently changed.',
      'legacy_2200_SS_accounts':
          'Zero-balance legacy accounts were preserved for audit; no deletion.',
      'unbalanced_gl_entries': 0,
      'integrity_check': 'ok',
    });

    stdout.writeln(
      'P0.005 DATA REPAIR PASS: 24 immutable AP reclassification entries created.',
    );
    stdout.writeln(
      'P0.005 supplier payments reclassified: 34,382.98 ILS.',
    );
    stdout.writeln('P0.005 legacy 2000.S* net balance: 0.00 ILS.');
    stdout.writeln(
      'P0.005 canonical supplier AP net balance: 41,434.00 ILS.',
    );
    stdout.writeln(
      'P0.005 supplier 13 debit balance preserved: 1,999.00 ILS '
      '(overpayment/advance).',
    );
    stdout.writeln('P0.005 GL balance validation PASS.');
    stdout.writeln('P0.005 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
