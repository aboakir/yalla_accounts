import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const dbPath = r'D:/YallaAccounts/yalla_accounts.db';

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  return asInt(rows.first.values.first);
}

Future<Map<String, Object?>> snapshot(Database db) async {
  final version = firstInt(await db.rawQuery('PRAGMA user_version'));

  final integrity = await db.rawQuery('PRAGMA integrity_check');
  final integrityOk = integrity.isNotEmpty &&
      integrity.first.values.first.toString().toLowerCase() == 'ok';

  final foreignKeys = (await db.rawQuery('PRAGMA foreign_key_check')).length;

  final unbalanced = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT e.id
        FROM gl_entries e
        LEFT JOIN gl_lines l ON l.entry_id=e.id
        GROUP BY e.id
        HAVING ABS(COALESCE(SUM(l.debit),0) -
                   COALESCE(SUM(l.credit),0)) > 0.01
      )
    '''),
  );

  final duplicateGl = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT source, source_id
        FROM gl_entries
        GROUP BY source, source_id
        HAVING COUNT(*) > 1
      )
    '''),
  );

  final missingDocumentGl = firstInt(
    await db.rawQuery(r'''
      SELECT
        (SELECT COUNT(*)
         FROM invoices i
         WHERE NOT EXISTS(
           SELECT 1 FROM gl_entries e
           WHERE e.source='INVOICE' AND e.source_id=i.id
         ))
        +
        (SELECT COUNT(*)
         FROM vouchers v
         WHERE NOT EXISTS(
           SELECT 1 FROM gl_entries e
           WHERE e.source='VOUCHER' AND e.source_id=v.id
         ))
        +
        (SELECT COUNT(*)
         FROM payments p
         WHERE p.isIncome=1
           AND NOT EXISTS(
             SELECT 1 FROM gl_entries e
             WHERE e.source='PAYMENT' AND e.source_id=p.id
           ))
        +
        (SELECT COUNT(*)
         FROM purchase_invoices p
         WHERE NOT EXISTS(
           SELECT 1 FROM gl_entries e
           WHERE e.source='PURCHASE' AND e.source_id=p.id
         ))
    '''),
  );

  final postingCacheMismatch = firstInt(
    await db.rawQuery(r'''
      SELECT
        (SELECT COUNT(*)
         FROM invoices i
         LEFT JOIN gl_entries e
           ON e.source='INVOICE' AND e.source_id=i.id
         WHERE COALESCE(i.post_to_gl,0) <>
               CASE WHEN e.id IS NULL THEN 0 ELSE 1 END
            OR COALESCE(i.gl_entry_id,0) <> COALESCE(e.id,0))
        +
        (SELECT COUNT(*)
         FROM vouchers v
         LEFT JOIN gl_entries e
           ON e.source='VOUCHER' AND e.source_id=v.id
         WHERE COALESCE(v.is_posted,0) <>
               CASE WHEN e.id IS NULL THEN 0 ELSE 1 END
            OR COALESCE(v.gl_entry_id,0) <> COALESCE(e.id,0))
        +
        (SELECT COUNT(*)
         FROM payments p
         LEFT JOIN gl_entries e
           ON e.source='PAYMENT' AND e.source_id=p.id
         WHERE e.id IS NOT NULL
           AND COALESCE(p.gl_entry_id,0) <> e.id)
    '''),
  );

  final repairLinkMismatch = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM repairs r
      JOIN invoices i ON i.repair_id=r.id
      WHERE COALESCE(r.invoice_id,'') <> i.id
    '''),
  );

  final repairInvoiceMismatch = await db.rawQuery(r'''
    SELECT
      COUNT(*) AS c,
      COALESCE(SUM(ABS(COALESCE(r.fileValue,0) -
                       COALESCE(i.total,0))),0) AS amount
    FROM repairs r
    JOIN invoices i ON i.repair_id=r.id
    WHERE ABS(COALESCE(r.fileValue,0) -
              COALESCE(i.total,0)) > 0.01
  ''');

  final repairLineIssues = firstInt(
    await db.rawQuery(r'''
      SELECT
        (SELECT COUNT(*)
         FROM repair_lines
         WHERE COALESCE(qty,0) <= 0)
        +
        (SELECT COUNT(*)
         FROM repair_lines
         WHERE ABS(COALESCE(total,0) -
                   (COALESCE(qty,0) * COALESCE(price,0))) > 0.01)
        +
        (SELECT COUNT(*)
         FROM repair_lines l
         LEFT JOIN repairs r ON r.id=l.repair_id
         WHERE r.id IS NULL)
    '''),
  );

  final legacySupplierBalance = await db.rawQuery(r'''
    SELECT
      COUNT(*) AS c,
      COALESCE(SUM(ABS(balance)),0) AS amount
    FROM (
      SELECT
        a.id,
        COALESCE(SUM(l.credit-l.debit),0) AS balance
      FROM accounts a
      LEFT JOIN gl_lines l ON l.account_id=a.id
      WHERE a.code LIKE '2000.S%'
         OR a.code LIKE '2200.SS%'
      GROUP BY a.id
      HAVING ABS(COALESCE(SUM(l.credit-l.debit),0)) > 0.01
    )
  ''');

  final supplierAdvances = await db.rawQuery(r'''
    SELECT
      COUNT(*) AS c,
      COALESCE(SUM(ABS(balance)),0) AS amount
    FROM (
      SELECT
        a.id,
        COALESCE(SUM(l.credit-l.debit),0) AS balance
      FROM accounts a
      LEFT JOIN gl_lines l ON l.account_id=a.id
      WHERE a.code GLOB '2200.S[0-9][0-9][0-9][0-9]'
      GROUP BY a.id
      HAVING COALESCE(SUM(l.credit-l.debit),0) < -0.01
    )
  ''');

  final chequeMissing = firstInt(
    await db.rawQuery(r'''
      SELECT
        (SELECT COUNT(*)
         FROM vouchers v
         WHERE LOWER(COALESCE(v.method,''))='cheque'
           AND NOT EXISTS(
             SELECT 1 FROM cheques c
             WHERE c.source_type='VOUCHER' AND c.source_id=v.id
           ))
        +
        (SELECT COUNT(*)
         FROM payments p
         WHERE LOWER(COALESCE(p.method,''))='cheque'
           AND NOT EXISTS(
             SELECT 1 FROM cheques c
             WHERE c.source_type='PAYMENT' AND c.source_id=p.id
           ))
    '''),
  );

  final incompleteCheques = firstInt(
    await db.rawQuery(
      'SELECT COUNT(*) FROM cheques '
      'WHERE COALESCE(is_legacy_incomplete,0)=1',
    ),
  );

  final repairHistoryNet = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT a.id
        FROM gl_lines l
        JOIN gl_entries e ON e.id=l.entry_id
        JOIN accounts a ON a.id=l.account_id
        WHERE e.source IN ('REPAIR_REV','REPAIR_ADJ','P0_REPAIR_FIX')
        GROUP BY a.id
        HAVING ABS(SUM(l.debit-l.credit)) > 0.01
      )
    '''),
  );

  final settlements = firstInt(
    await db.rawQuery('SELECT COUNT(*) FROM invoice_settlements'),
  );

  final settlementInfo = await db.rawQuery(
    'PRAGMA table_info(invoice_settlements)',
  );
  var settlementInvoiceType = 'MISSING';
  for (final column in settlementInfo) {
    if (column['name']?.toString() == 'invoice_id') {
      settlementInvoiceType = (column['type'] ?? '').toString().toUpperCase();
    }
  }

  final glTotals = await db.rawQuery(r'''
    SELECT
      COUNT(*) AS line_count,
      COALESCE(SUM(debit),0) AS debit,
      COALESCE(SUM(credit),0) AS credit
    FROM gl_lines
  ''');

  final canonicalAp = await db.rawQuery(r'''
    SELECT COALESCE(SUM(balance),0) AS balance
    FROM (
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS balance
      FROM accounts a
      LEFT JOIN gl_lines l ON l.account_id=a.id
      WHERE a.code GLOB '2200.S[0-9][0-9][0-9][0-9]'
      GROUP BY a.id
    )
  ''');

  final account1020 = await db.rawQuery(r'''
    SELECT COALESCE(SUM(l.debit-l.credit),0) AS balance
    FROM gl_lines l
    JOIN accounts a ON a.id=l.account_id
    WHERE a.code='1020'
  ''');

  final account1030 = await db.rawQuery(r'''
    SELECT COALESCE(SUM(l.credit-l.debit),0) AS balance
    FROM gl_lines l
    JOIN accounts a ON a.id=l.account_id
    WHERE a.code='1030'
  ''');

  return {
    'db_version': version,
    'integrity_ok': integrityOk,
    'foreign_key_violations': foreignKeys,
    'unbalanced_gl_entries': unbalanced,
    'duplicate_gl_sources': duplicateGl,
    'missing_document_gl': missingDocumentGl,
    'posting_cache_mismatch': postingCacheMismatch,
    'repair_invoice_link_mismatch': repairLinkMismatch,
    'repair_invoice_mismatch_count': asInt(repairInvoiceMismatch.first['c']),
    'repair_invoice_mismatch_abs_ils':
        asDouble(repairInvoiceMismatch.first['amount']),
    'repair_line_issues': repairLineIssues,
    'legacy_supplier_balance_count': asInt(legacySupplierBalance.first['c']),
    'legacy_supplier_balance_abs_ils':
        asDouble(legacySupplierBalance.first['amount']),
    'supplier_advance_count': asInt(supplierAdvances.first['c']),
    'supplier_advance_abs_ils': asDouble(supplierAdvances.first['amount']),
    'cheque_missing_instrument': chequeMissing,
    'legacy_incomplete_cheques': incompleteCheques,
    'repair_history_net_accounts': repairHistoryNet,
    'settlement_count': settlements,
    'settlement_invoice_id_type': settlementInvoiceType,
    'repairs': firstInt(await db.rawQuery('SELECT COUNT(*) FROM repairs')),
    'invoices': firstInt(await db.rawQuery('SELECT COUNT(*) FROM invoices')),
    'vouchers': firstInt(await db.rawQuery('SELECT COUNT(*) FROM vouchers')),
    'receipts': firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM payments WHERE isIncome=1'),
    ),
    'purchase_invoices':
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM purchase_invoices')),
    'repair_lines':
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM repair_lines')),
    'cheques': firstInt(await db.rawQuery('SELECT COUNT(*) FROM cheques')),
    'cheque_events':
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM cheque_events')),
    'gl_entries':
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM gl_entries')),
    'gl_lines': asInt(glTotals.first['line_count']),
    'gl_debit_total': asDouble(glTotals.first['debit']),
    'gl_credit_total': asDouble(glTotals.first['credit']),
    'invoice_total_ils': asDouble(
      (await db.rawQuery(
        'SELECT COALESCE(SUM(total),0) AS s FROM invoices',
      ))
          .first['s'],
    ),
    'repair_file_value_total_ils': asDouble(
      (await db.rawQuery(
        'SELECT COALESCE(SUM(fileValue),0) AS s FROM repairs',
      ))
          .first['s'],
    ),
    'voucher_total_ils': asDouble(
      (await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS s FROM vouchers',
      ))
          .first['s'],
    ),
    'receipt_total_ils': asDouble(
      (await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS s '
        'FROM payments WHERE isIncome=1',
      ))
          .first['s'],
    ),
    'purchase_amount_total_ils': asDouble(
      (await db.rawQuery(
        'SELECT COALESCE(SUM(amount_total),0) AS s '
        'FROM purchase_invoices',
      ))
          .first['s'],
    ),
    'canonical_supplier_ap_ils': asDouble(canonicalAp.first['balance']),
    'account_1020_net_ils': asDouble(account1020.first['balance']),
    'account_1030_credit_ils': asDouble(account1030.first['balance']),
    'p0_dup_rev': firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM gl_entries WHERE source='P0_DUP_REV'",
      ),
    ),
    'p0_repair_fix': firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM gl_entries WHERE source='P0_REPAIR_FIX'",
      ),
    ),
    'p0_ap_reclass': firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM gl_entries WHERE source='P0_AP_RECLASS'",
      ),
    ),
    'p0_cheque_fix': firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM gl_entries WHERE source='P0_CHEQUE_FIX'",
      ),
    ),
  };
}

void requireClose(
  String name,
  double actual,
  double expected, {
  double tolerance = 0.01,
}) {
  if ((actual - expected).abs() > tolerance) {
    throw StateError(
      '$name changed: expected $expected, found $actual',
    );
  }
}

void validateBaseline(Map<String, Object?> s) {
  final version = asInt(s['db_version']);
  if (version != 57 && version != 58) {
    throw StateError('P0.010 expected DB v57/v58, found v$version');
  }

  if (s['integrity_ok'] != true ||
      asInt(s['foreign_key_violations']) != 0 ||
      asInt(s['unbalanced_gl_entries']) != 0 ||
      asInt(s['duplicate_gl_sources']) != 0 ||
      asInt(s['missing_document_gl']) != 0 ||
      asInt(s['posting_cache_mismatch']) != 0 ||
      asInt(s['repair_invoice_link_mismatch']) != 0 ||
      asInt(s['repair_line_issues']) != 0 ||
      asInt(s['legacy_supplier_balance_count']) != 0 ||
      asInt(s['cheque_missing_instrument']) != 0 ||
      asInt(s['repair_history_net_accounts']) != 0) {
    throw StateError('P0.010 blocking invariant failed: $s');
  }

  if (asInt(s['repairs']) != 114 ||
      asInt(s['invoices']) != 113 ||
      asInt(s['vouchers']) != 55 ||
      asInt(s['receipts']) != 37 ||
      asInt(s['purchase_invoices']) != 61 ||
      asInt(s['repair_lines']) != 984 ||
      asInt(s['cheques']) != 1 ||
      asInt(s['cheque_events']) != 2 ||
      asInt(s['gl_entries']) != 445 ||
      asInt(s['gl_lines']) != 1040 ||
      asInt(s['repair_invoice_mismatch_count']) != 33 ||
      asInt(s['supplier_advance_count']) != 1 ||
      asInt(s['legacy_incomplete_cheques']) != 1 ||
      asInt(s['p0_dup_rev']) != 4 ||
      asInt(s['p0_repair_fix']) != 71 ||
      asInt(s['p0_ap_reclass']) != 24 ||
      asInt(s['p0_cheque_fix']) != 1) {
    throw StateError('P0.010 audited counts changed: $s');
  }

  requireClose(
    'repair/invoice warning amount',
    asDouble(s['repair_invoice_mismatch_abs_ils']),
    47150.0,
  );
  requireClose(
    'supplier advance',
    asDouble(s['supplier_advance_abs_ils']),
    1999.0,
  );
  requireClose(
    'GL debit',
    asDouble(s['gl_debit_total']),
    1305517.93555,
    tolerance: 0.001,
  );
  requireClose(
    'GL credit',
    asDouble(s['gl_credit_total']),
    1305517.93555,
    tolerance: 0.001,
  );
  requireClose(
    'invoice total',
    asDouble(s['invoice_total_ils']),
    337560.0,
  );
  requireClose(
    'repair fileValue total',
    asDouble(s['repair_file_value_total_ils']),
    372110.0,
  );
  requireClose(
    'voucher total',
    asDouble(s['voucher_total_ils']),
    61202.98,
  );
  requireClose(
    'receipt total',
    asDouble(s['receipt_total_ils']),
    85185.0,
  );
  requireClose(
    'purchase amount total',
    asDouble(s['purchase_amount_total_ils']),
    75816.97555,
    tolerance: 0.001,
  );
  requireClose(
    'canonical supplier AP',
    asDouble(s['canonical_supplier_ap_ils']),
    41433.99555,
    tolerance: 0.001,
  );
  requireClose(
    'account 1020',
    asDouble(s['account_1020_net_ils']),
    0.0,
  );
  requireClose(
    'account 1030',
    asDouble(s['account_1030_credit_ils']),
    2000.0,
  );
}

Future<void> ensureV58Schema(Database db) async {
  final table = await db.rawQuery(
    "SELECT name FROM sqlite_master "
    "WHERE type='table' AND name='invoice_settlements'",
  );

  if (table.isEmpty) {
    await db.execute(r'''
      CREATE TABLE invoice_settlements (
        id TEXT PRIMARY KEY,
        supplier_id INTEGER NOT NULL,
        invoice_id TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        amount_applied REAL NOT NULL,
        created_at TEXT
      )
    ''');
  } else {
    final info = await db.rawQuery(
      'PRAGMA table_info(invoice_settlements)',
    );

    var type = '';
    for (final column in info) {
      if (column['name']?.toString() == 'invoice_id') {
        type = (column['type'] ?? '').toString().toUpperCase();
      }
    }

    if (type != 'TEXT') {
      await db.transaction((txn) async {
        await txn.execute(
          'DROP TABLE IF EXISTS invoice_settlements_v58',
        );

        await txn.execute(r'''
          CREATE TABLE invoice_settlements_v58 (
            id TEXT PRIMARY KEY,
            supplier_id INTEGER NOT NULL,
            invoice_id TEXT NOT NULL,
            voucher_id TEXT NOT NULL,
            amount_applied REAL NOT NULL,
            created_at TEXT
          )
        ''');

        await txn.execute(r'''
          INSERT INTO invoice_settlements_v58(
            id,
            supplier_id,
            invoice_id,
            voucher_id,
            amount_applied,
            created_at
          )
          SELECT
            id,
            supplier_id,
            CAST(invoice_id AS TEXT),
            voucher_id,
            amount_applied,
            created_at
          FROM invoice_settlements
        ''');

        await txn.execute('DROP TABLE invoice_settlements');
        await txn.execute(
          'ALTER TABLE invoice_settlements_v58 '
          'RENAME TO invoice_settlements',
        );
      });
    }
  }

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_settlements_supplier '
    'ON invoice_settlements(supplier_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_settlements_invoice '
    'ON invoice_settlements(invoice_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_settlements_voucher '
    'ON invoice_settlements(voucher_id)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_settlements_voucher_invoice '
    'ON invoice_settlements(voucher_id, invoice_id)',
  );

  await db.execute(r'''
    CREATE TABLE IF NOT EXISTS data_health_repair_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_at TEXT NOT NULL,
      backup_path TEXT,
      changes_json TEXT NOT NULL,
      before_summary TEXT,
      after_summary TEXT
    )
  ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_data_health_repair_log_run_at '
    'ON data_health_repair_log(run_at)',
  );

  await db.execute('PRAGMA user_version = 58');
}

Future<void> writeReport(Map<String, Object?> body) async {
  final home = Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return;

  final file = File(
    '$home${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}Yalla_P0_010_RESULT.json',
  );

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(body),
    flush: true,
  );
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(dbPath).existsSync()) {
    stderr.writeln('P0.010 ERROR: DB not found at $dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(dbPath);

  try {
    final before = await snapshot(db);
    validateBaseline(before);

    stdout.writeln(
      'P0.010 preflight PASS: no blocking accounting/data-health errors.',
    );
    stdout.writeln(
      'Expected review warnings: 33 Repair/Invoice differences, '
      '1 supplier advance (1,999 ILS), 1 legacy incomplete cheque.',
    );

    if (!apply) return;

    final glLinesBefore = asInt(before['gl_lines']);
    final glDebitBefore = asDouble(before['gl_debit_total']);
    final glCreditBefore = asDouble(before['gl_credit_total']);
    final invoiceTotalBefore = asDouble(before['invoice_total_ils']);
    final repairTotalBefore = asDouble(before['repair_file_value_total_ils']);
    final voucherTotalBefore = asDouble(before['voucher_total_ils']);
    final receiptTotalBefore = asDouble(before['receipt_total_ils']);
    final purchaseTotalBefore = asDouble(before['purchase_amount_total_ils']);

    await ensureV58Schema(db);

    final after = await snapshot(db);
    validateBaseline(after);

    if (asInt(after['db_version']) != 58 ||
        after['settlement_invoice_id_type'] != 'TEXT') {
      throw StateError(
        'P0.010 v58 schema validation failed: $after',
      );
    }

    if (asInt(after['gl_lines']) != glLinesBefore) {
      throw StateError('P0.010 changed GL line count.');
    }

    requireClose(
      'GL debit after P0.010',
      asDouble(after['gl_debit_total']),
      glDebitBefore,
      tolerance: 0.001,
    );
    requireClose(
      'GL credit after P0.010',
      asDouble(after['gl_credit_total']),
      glCreditBefore,
      tolerance: 0.001,
    );
    requireClose(
      'invoice total after P0.010',
      asDouble(after['invoice_total_ils']),
      invoiceTotalBefore,
    );
    requireClose(
      'repair fileValue after P0.010',
      asDouble(after['repair_file_value_total_ils']),
      repairTotalBefore,
    );
    requireClose(
      'voucher total after P0.010',
      asDouble(after['voucher_total_ils']),
      voucherTotalBefore,
    );
    requireClose(
      'receipt total after P0.010',
      asDouble(after['receipt_total_ils']),
      receiptTotalBefore,
    );
    requireClose(
      'purchase total after P0.010',
      asDouble(after['purchase_amount_total_ils']),
      purchaseTotalBefore,
      tolerance: 0.001,
    );

    await db.insert(
      'data_health_repair_log',
      {
        'run_at': DateTime.now().toIso8601String(),
        'backup_path': 'P0.010 apply.ps1 backup',
        'changes_json': jsonEncode({
          'database_version': '57 -> 58',
          'invoice_settlements_invoice_id': 'INTEGER -> TEXT',
          'permanent_health_tool': true,
        }),
        'before_summary': jsonEncode({
          'blocking_errors': 0,
          'warnings': 3,
        }),
        'after_summary': jsonEncode({
          'blocking_errors': 0,
          'warnings': 3,
        }),
      },
    );

    await writeReport({
      'status': 'PASS',
      'database_version': 58,
      'blocking_errors': 0,
      'repairable_after_bootstrap': 0,
      'review_warnings': {
        'repair_invoice_differences': 33,
        'repair_invoice_abs_ils': 47150.0,
        'supplier_advances': 1,
        'supplier_advance_ils': 1999.0,
        'legacy_incomplete_cheques': 1,
      },
      'p0_invariants': {
        'duplicate_gl_sources': 0,
        'unbalanced_gl_entries': 0,
        'missing_document_gl': 0,
        'posting_cache_mismatch': 0,
        'repair_invoice_link_mismatch': 0,
        'repair_line_issues': 0,
        'legacy_supplier_balance_count': 0,
        'cheque_missing_instrument': 0,
        'repair_history_net_accounts': 0,
      },
      'financial_history_changed': false,
      'gl_debit_total': after['gl_debit_total'],
      'gl_credit_total': after['gl_credit_total'],
      'integrity_check': 'ok',
      'foreign_key_violations': 0,
    });

    stdout.writeln('P0.010 DB v58 schema PASS.');
    stdout.writeln('P0.010 permanent health infrastructure PASS.');
    stdout.writeln('P0.010 blocking errors: 0.');
    stdout.writeln('P0.010 repairable bootstrap issues: 0.');
    stdout.writeln('P0.010 review warnings preserved: 3.');
    stdout.writeln('P0.010 historical financial totals unchanged: PASS.');
    stdout.writeln('P0.010 GL balance validation PASS.');
    stdout.writeln('P0.010 foreign-key validation PASS.');
    stdout.writeln('P0.010 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
