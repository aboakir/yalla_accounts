import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const dbPath = r'D:/YallaAccounts/yalla_accounts.db';

double asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  return asInt(rows.first.values.first);
}

double round2(double value) => double.parse(value.toStringAsFixed(2));

List<Map<String, dynamic>> decodeList(Object? raw) {
  if (raw == null) return <Map<String, dynamic>>[];

  dynamic decoded = raw;

  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return <Map<String, dynamic>>[];
    decoded = jsonDecode(text);
  }

  if (decoded is! List) return <Map<String, dynamic>>[];

  return decoded
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Map<String, dynamic>? normalizeItem(Map<String, dynamic> item) {
  final name = (item['name'] ?? '').toString().trim();
  if (name.isEmpty) return null;

  var qty = asDouble(item['qty']);
  if (qty <= 0) qty = 1.0;

  final price = asDouble(
    item['price'] ?? item['amount'] ?? item['cost'],
  );

  if (price < 0) {
    throw StateError('Negative repair-line price is not allowed: $name');
  }

  return <String, dynamic>{
    ...item,
    'name': name,
    'qty': qty,
    'price': price,
    'total': round2(qty * price),
  };
}

Future<void> writeReport(Map<String, Object?> body) async {
  final home = Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return;

  final file = File(
    '$home${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}Yalla_P0_009_RESULT.json',
  );

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(body),
    flush: true,
  );
}

Future<Map<String, Object?>> sqlSnapshot(Database db) async {
  final version = firstInt(await db.rawQuery('PRAGMA user_version'));
  final repairCount =
      firstInt(await db.rawQuery('SELECT COUNT(*) FROM repairs'));
  final lineCount =
      firstInt(await db.rawQuery('SELECT COUNT(*) FROM repair_lines'));
  final qtyNonPositive = firstInt(
    await db.rawQuery(
      'SELECT COUNT(*) FROM repair_lines WHERE COALESCE(qty,0) <= 0',
    ),
  );
  final monetaryQtyBad = firstInt(
    await db.rawQuery(
      '''
      SELECT COUNT(*)
      FROM repair_lines
      WHERE COALESCE(price,0) > 0.01 AND COALESCE(qty,0) <= 0
      ''',
    ),
  );
  final pricePositiveTotalZero = firstInt(
    await db.rawQuery(
      '''
      SELECT COUNT(*)
      FROM repair_lines
      WHERE COALESCE(price,0) > 0.01
        AND ABS(COALESCE(total,0)) <= 0.01
      ''',
    ),
  );
  final formulaMismatch = firstInt(
    await db.rawQuery(
      '''
      SELECT COUNT(*)
      FROM repair_lines
      WHERE ABS(
        COALESCE(total,0) - COALESCE(qty,0) * COALESCE(price,0)
      ) > 0.01
      ''',
    ),
  );
  final orphanLines = firstInt(
    await db.rawQuery(
      '''
      SELECT COUNT(*)
      FROM repair_lines l
      LEFT JOIN repairs r ON r.id=l.repair_id
      WHERE r.id IS NULL
      ''',
    ),
  );
  final partCount = firstInt(
    await db.rawQuery(
      "SELECT COUNT(*) FROM repair_lines WHERE line_type='part'",
    ),
  );
  final workCount = firstInt(
    await db.rawQuery(
      "SELECT COUNT(*) FROM repair_lines WHERE line_type='work'",
    ),
  );
  final lineSums = await db.rawQuery(
    '''
    SELECT
      COALESCE(SUM(price),0) AS price_sum,
      COALESCE(SUM(total),0) AS total_sum
    FROM repair_lines
    ''',
  );
  final repairFileValue = await db.rawQuery(
    'SELECT COALESCE(SUM(fileValue),0) AS s FROM repairs',
  );
  final invoiceFinancial = await db.rawQuery(
    '''
    SELECT COUNT(*) AS c, COALESCE(SUM(total),0) AS s
    FROM invoices
    ''',
  );
  final glFinancial = await db.rawQuery(
    '''
    SELECT
      COUNT(*) AS c,
      COALESCE(SUM(debit),0) AS d,
      COALESCE(SUM(credit),0) AS cr
    FROM gl_lines
    ''',
  );
  final glEntryCount =
      firstInt(await db.rawQuery('SELECT COUNT(*) FROM gl_entries'));
  final unbalanced = firstInt(
    await db.rawQuery(
      '''
      SELECT COUNT(*)
      FROM (
        SELECT entry_id, SUM(debit-credit) AS diff
        FROM gl_lines
        GROUP BY entry_id
        HAVING ABS(diff) > 0.01
      )
      ''',
    ),
  );
  final integrity = await db.rawQuery('PRAGMA integrity_check');
  final fk = await db.rawQuery('PRAGMA foreign_key_check');

  return <String, Object?>{
    'user_version': version,
    'repair_count': repairCount,
    'repair_line_count': lineCount,
    'qty_nonpositive': qtyNonPositive,
    'monetary_qty_bad': monetaryQtyBad,
    'price_positive_total_zero': pricePositiveTotalZero,
    'formula_mismatch': formulaMismatch,
    'orphan_lines': orphanLines,
    'part_count': partCount,
    'work_count': workCount,
    'line_price_sum': asDouble(lineSums.first['price_sum']),
    'line_total_sum': asDouble(lineSums.first['total_sum']),
    'repair_file_value_sum': asDouble(repairFileValue.first['s']),
    'invoice_count': asInt(invoiceFinancial.first['c']),
    'invoice_total_sum': asDouble(invoiceFinancial.first['s']),
    'gl_entry_count': glEntryCount,
    'gl_line_count': asInt(glFinancial.first['c']),
    'gl_debit_sum': asDouble(glFinancial.first['d']),
    'gl_credit_sum': asDouble(glFinancial.first['cr']),
    'unbalanced_gl_entries': unbalanced,
    'integrity_ok':
        integrity.isNotEmpty && integrity.first.values.first.toString() == 'ok',
    'foreign_key_violations': fk.length,
  };
}

Future<Map<String, Object?>> jsonSnapshot(Database db) async {
  final repairs = await db.query(
    'repairs',
    columns: ['id', 'parts', 'works', 'fileValue'],
  );

  var itemCount = 0;
  var partCount = 0;
  var workCount = 0;
  var qtyMissing = 0;
  var totalMissing = 0;
  var normalizedTotal = 0.0;
  var fileValueMismatchCount = 0;

  for (final repair in repairs) {
    var repairTotal = 0.0;

    void inspectType(String type, Object? raw) {
      final decoded = decodeList(raw);

      for (final item in decoded) {
        itemCount++;
        if (type == 'part') {
          partCount++;
        } else {
          workCount++;
        }

        if (item['qty'] == null) qtyMissing++;
        if (item['total'] == null) totalMissing++;

        final normalized = normalizeItem(item);
        if (normalized == null) continue;

        final total = asDouble(normalized['total']);
        repairTotal += total;
        normalizedTotal += total;
      }
    }

    inspectType('part', repair['parts']);
    inspectType('work', repair['works']);

    final fileValue = asDouble(repair['fileValue']);
    if ((repairTotal - fileValue).abs() > 0.01) {
      fileValueMismatchCount++;
    }
  }

  return <String, Object?>{
    'json_item_count': itemCount,
    'json_part_count': partCount,
    'json_work_count': workCount,
    'json_qty_missing': qtyMissing,
    'json_total_missing': totalMissing,
    'json_normalized_total': normalizedTotal,
    'json_vs_file_value_mismatch_count': fileValueMismatchCount,
  };
}

Future<void> rebuild(DatabaseExecutor db) async {
  final repairs = await db.query(
    'repairs',
    columns: ['id', 'parts', 'works', 'fileValue', 'created_at'],
  );

  await db.execute('DROP TABLE IF EXISTS repair_lines_v57;');
  await db.execute(
    '''
    CREATE TABLE repair_lines_v57(
      id TEXT PRIMARY KEY,
      repair_id TEXT NOT NULL,
      line_type TEXT NOT NULL CHECK(line_type IN ('work','part')),
      name TEXT NOT NULL CHECK(LENGTH(TRIM(name)) > 0),
      qty REAL NOT NULL DEFAULT 1 CHECK(qty > 0),
      price REAL NOT NULL DEFAULT 0 CHECK(price >= 0),
      total REAL NOT NULL DEFAULT 0
        CHECK(total >= 0 AND ABS(total - (qty * price)) <= 0.01),
      notes TEXT,
      created_at TEXT,
      FOREIGN KEY(repair_id) REFERENCES repairs(id) ON DELETE CASCADE
    )
    ''',
  );

  for (final repair in repairs) {
    final repairId = repair['id']?.toString() ?? '';
    if (repairId.isEmpty) {
      throw StateError('P0.009 found Repair without id.');
    }

    final normalizedParts = <Map<String, dynamic>>[];
    final normalizedWorks = <Map<String, dynamic>>[];
    var normalizedRepairTotal = 0.0;

    Future<void> insertType(
      String type,
      Object? raw,
      List<Map<String, dynamic>> target,
    ) async {
      final decoded = decodeList(raw);

      for (var index = 0; index < decoded.length; index++) {
        final normalized = normalizeItem(decoded[index]);
        if (normalized == null) continue;

        target.add(normalized);
        normalizedRepairTotal += asDouble(normalized['total']);

        await db.insert(
          'repair_lines_v57',
          <String, Object?>{
            'id': '$repairId:$type:$index',
            'repair_id': repairId,
            'line_type': type,
            'name': normalized['name'],
            'qty': normalized['qty'],
            'price': normalized['price'],
            'total': normalized['total'],
            'notes': normalized['notes'],
            'created_at': repair['created_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    }

    await insertType(
      'part',
      repair['parts'],
      normalizedParts,
    );
    await insertType(
      'work',
      repair['works'],
      normalizedWorks,
    );

    final storedFileValue = asDouble(repair['fileValue']);
    if ((normalizedRepairTotal - storedFileValue).abs() > 0.01) {
      throw StateError(
        'P0.009 refused to rewrite Repair $repairId because normalized '
        'detail does not match stored fileValue.',
      );
    }

    await db.update(
      'repairs',
      <String, Object?>{
        'parts': jsonEncode(normalizedParts),
        'works': jsonEncode(normalizedWorks),
      },
      where: 'id = ?',
      whereArgs: <Object?>[repairId],
    );
  }

  await db.execute('DROP TABLE repair_lines;');
  await db.execute(
    'ALTER TABLE repair_lines_v57 RENAME TO repair_lines;',
  );
  await db.execute(
    'CREATE INDEX idx_repair_lines_repair ON repair_lines(repair_id);',
  );
  await db.execute(
    'CREATE INDEX idx_repair_lines_type ON repair_lines(line_type);',
  );
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(dbPath).existsSync()) {
    stderr.writeln('P0.009 ERROR: DB not found at $dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(dbPath);

  try {
    await db.execute('PRAGMA foreign_keys=ON;');

    final beforeSql = await sqlSnapshot(db);
    final beforeJson = await jsonSnapshot(db);

    final baselineOk = beforeSql['user_version'] == 56 &&
        beforeSql['repair_count'] == 114 &&
        beforeSql['repair_line_count'] == 990 &&
        beforeSql['qty_nonpositive'] == 990 &&
        beforeSql['monetary_qty_bad'] == 386 &&
        beforeSql['price_positive_total_zero'] == 386 &&
        beforeSql['formula_mismatch'] == 0 &&
        beforeSql['orphan_lines'] == 0 &&
        beforeSql['part_count'] == 529 &&
        beforeSql['work_count'] == 461 &&
        (asDouble(beforeSql['line_price_sum']) - 364550.0).abs() <= 0.01 &&
        asDouble(beforeSql['line_total_sum']).abs() <= 0.01 &&
        (asDouble(beforeSql['repair_file_value_sum']) - 372110.0).abs() <=
            0.01 &&
        beforeSql['invoice_count'] == 113 &&
        (asDouble(beforeSql['invoice_total_sum']) - 337560.0).abs() <= 0.01 &&
        beforeSql['gl_entry_count'] == 445 &&
        beforeSql['gl_line_count'] == 1040 &&
        (asDouble(beforeSql['gl_debit_sum']) - 1305517.93555).abs() <= 0.001 &&
        (asDouble(beforeSql['gl_credit_sum']) - 1305517.93555).abs() <= 0.001 &&
        beforeSql['unbalanced_gl_entries'] == 0 &&
        beforeSql['integrity_ok'] == true &&
        beforeSql['foreign_key_violations'] == 0 &&
        beforeJson['json_item_count'] == 984 &&
        beforeJson['json_part_count'] == 515 &&
        beforeJson['json_work_count'] == 469 &&
        beforeJson['json_qty_missing'] == 853 &&
        beforeJson['json_total_missing'] == 566 &&
        (asDouble(beforeJson['json_normalized_total']) - 372110.0).abs() <=
            0.01 &&
        beforeJson['json_vs_file_value_mismatch_count'] == 0;

    if (!baselineOk) {
      throw StateError(
        'P0.009 refused: live DB changed since audited preflight. '
        'SQL=$beforeSql JSON=$beforeJson',
      );
    }

    stdout.writeln(
      'P0.009 preflight PASS: 990 legacy repair_lines are stale/derived.',
    );
    stdout.writeln(
      'Canonical Repair JSON contains 984 items and exactly matches '
      '372,110.00 ILS total fileValue.',
    );
    stdout.writeln(
      'Historical accounting will not be rewritten.',
    );

    if (!apply) return;

    final financialBefore = <String, Object?>{
      'invoice_count': beforeSql['invoice_count'],
      'invoice_total_sum': beforeSql['invoice_total_sum'],
      'gl_entry_count': beforeSql['gl_entry_count'],
      'gl_line_count': beforeSql['gl_line_count'],
      'gl_debit_sum': beforeSql['gl_debit_sum'],
      'gl_credit_sum': beforeSql['gl_credit_sum'],
      'repair_file_value_sum': beforeSql['repair_file_value_sum'],
    };

    await db.transaction((txn) async {
      await rebuild(txn);
    });

    await db.execute('PRAGMA user_version=57;');

    final afterSql = await sqlSnapshot(db);
    final afterJson = await jsonSnapshot(db);

    final financialAfter = <String, Object?>{
      'invoice_count': afterSql['invoice_count'],
      'invoice_total_sum': afterSql['invoice_total_sum'],
      'gl_entry_count': afterSql['gl_entry_count'],
      'gl_line_count': afterSql['gl_line_count'],
      'gl_debit_sum': afterSql['gl_debit_sum'],
      'gl_credit_sum': afterSql['gl_credit_sum'],
      'repair_file_value_sum': afterSql['repair_file_value_sum'],
    };

    final afterOk = afterSql['user_version'] == 57 &&
        afterSql['repair_count'] == 114 &&
        afterSql['repair_line_count'] == 984 &&
        afterSql['qty_nonpositive'] == 0 &&
        afterSql['monetary_qty_bad'] == 0 &&
        afterSql['price_positive_total_zero'] == 0 &&
        afterSql['formula_mismatch'] == 0 &&
        afterSql['orphan_lines'] == 0 &&
        afterSql['part_count'] == 515 &&
        afterSql['work_count'] == 469 &&
        (asDouble(afterSql['line_price_sum']) - 372110.0).abs() <= 0.01 &&
        (asDouble(afterSql['line_total_sum']) - 372110.0).abs() <= 0.01 &&
        afterJson['json_item_count'] == 984 &&
        afterJson['json_part_count'] == 515 &&
        afterJson['json_work_count'] == 469 &&
        afterJson['json_qty_missing'] == 0 &&
        afterJson['json_total_missing'] == 0 &&
        (asDouble(afterJson['json_normalized_total']) - 372110.0).abs() <=
            0.01 &&
        afterJson['json_vs_file_value_mismatch_count'] == 0 &&
        afterSql['unbalanced_gl_entries'] == 0 &&
        afterSql['integrity_ok'] == true &&
        afterSql['foreign_key_violations'] == 0;

    if (!afterOk) {
      throw StateError(
        'P0.009 post-validation failed. SQL=$afterSql JSON=$afterJson',
      );
    }

    bool sameFinancial(String key, {double tolerance = 0.001}) {
      final before = financialBefore[key];
      final after = financialAfter[key];

      if (before is num || after is num) {
        return (asDouble(before) - asDouble(after)).abs() <= tolerance;
      }

      return before == after;
    }

    final financialUnchanged = sameFinancial('invoice_count') &&
        sameFinancial('invoice_total_sum', tolerance: 0.01) &&
        sameFinancial('gl_entry_count') &&
        sameFinancial('gl_line_count') &&
        sameFinancial('gl_debit_sum') &&
        sameFinancial('gl_credit_sum') &&
        sameFinancial('repair_file_value_sum', tolerance: 0.01);

    if (!financialUnchanged) {
      throw StateError(
        'P0.009 financial invariants changed. '
        'before=$financialBefore after=$financialAfter',
      );
    }

    await writeReport(<String, Object?>{
      'status': 'PASS',
      'database_version': 57,
      'canonical_repair_detail': 'repairs.parts + repairs.works JSON',
      'repair_lines_role': 'normalized derived/query table',
      'legacy_repair_lines_before': 990,
      'canonical_lines_after': 984,
      'qty_nonpositive_after': 0,
      'formula_mismatch_after': 0,
      'repair_line_total_ils': 372110.0,
      'repair_file_value_total_ils': 372110.0,
      'json_qty_missing_after': 0,
      'json_total_missing_after': 0,
      'invoice_financial_history_changed': false,
      'gl_financial_history_changed': false,
      'repair_file_values_changed': false,
      'unbalanced_gl_entries': 0,
      'foreign_key_violations': 0,
      'integrity_check': 'ok',
    });

    stdout.writeln(
      'P0.009 DATA REPAIR PASS: repair_lines rebuilt from canonical Repair JSON.',
    );
    stdout.writeln(
      'P0.009 repair lines: 984 normalized rows / qty>0 / totals consistent.',
    );
    stdout.writeln(
      'P0.009 Repair JSON normalized: qty and total explicit on every item.',
    );
    stdout.writeln(
      'P0.009 Repair fileValue total unchanged: 372,110.00 ILS.',
    );
    stdout.writeln(
      'P0.009 Invoice/GL financial history unchanged: PASS.',
    );
    stdout.writeln('P0.009 DB version 57: PASS.');
    stdout.writeln('P0.009 GL balance validation PASS.');
    stdout.writeln('P0.009 foreign-key validation PASS.');
    stdout.writeln('P0.009 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
