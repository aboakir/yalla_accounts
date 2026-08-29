import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const dbPath = r'D:/YallaAccounts/yalla_accounts.db';
const repairWithoutInvoice = 'be996586-0a43-4c82-bf8d-520e0b8b865b';
const p0004Repair = '89fb8c7a-ef8a-462a-8aaf-6cb42d717974';

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final v = rows.first.values.first;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double number(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

Future<void> report(Map<String, Object?> body) async {
  final home = Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return;
  final file = File(
    '$home${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}Yalla_P0_006_RESULT.json',
  );
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(body),
    flush: true,
  );
}

Future<Map<String, Object?>> snapshot(Database db) async {
  final repairs = firstInt(
    await db.rawQuery('SELECT COUNT(*) FROM repairs'),
  );
  final invoices = firstInt(
    await db.rawQuery('SELECT COUNT(*) FROM invoices'),
  );
  final duplicateRepairInvoices = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT repair_id
        FROM invoices
        WHERE repair_id IS NOT NULL AND TRIM(repair_id) <> ''
        GROUP BY repair_id
        HAVING COUNT(*) > 1
      )
    '''),
  );
  final orphanInvoices = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM invoices i
      LEFT JOIN repairs r ON r.id=i.repair_id
      WHERE r.id IS NULL
    '''),
  );
  final repairsWithInvoice = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(DISTINCT repair_id)
      FROM invoices
      WHERE repair_id IS NOT NULL AND TRIM(repair_id) <> ''
    '''),
  );
  final canonicalLinks = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM repairs r
      JOIN invoices i ON i.repair_id=r.id
      WHERE r.invoice_id=i.id
    '''),
  );
  final missingCanonicalLinks = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM repairs r
      JOIN invoices i ON i.repair_id=r.id
      WHERE COALESCE(r.invoice_id,'') <> i.id
    '''),
  );
  final amountMismatch = await db.rawQuery(r'''
    SELECT
      COUNT(*) AS c,
      COALESCE(SUM(ABS(r.fileValue-i.total)),0) AS abs_diff,
      COALESCE(SUM(r.fileValue-i.total),0) AS net_diff
    FROM repairs r
    JOIN invoices i ON i.repair_id=r.id
    WHERE ABS(COALESCE(r.fileValue,0)-COALESCE(i.total,0)) > 0.01
  ''');
  final noInvoice = await db.rawQuery(r'''
    SELECT r.id, r.fileValue
    FROM repairs r
    WHERE NOT EXISTS (
      SELECT 1 FROM invoices i WHERE i.repair_id=r.id
    )
    ORDER BY r.id
  ''');
  final unbalanced = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT entry_id, SUM(debit-credit) diff
        FROM gl_lines
        GROUP BY entry_id
        HAVING ABS(diff) > 0.01
      )
    '''),
  );
  final invoiceGlCoverage = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM invoices i
      WHERE EXISTS (
        SELECT 1 FROM gl_entries e
        WHERE e.source='INVOICE' AND e.source_id=i.id
      )
    '''),
  );
  final p0005 = firstInt(
    await db.rawQuery(
      "SELECT COUNT(*) FROM gl_entries WHERE source='P0_AP_RECLASS'",
    ),
  );
  final integrity = await db.rawQuery('PRAGMA integrity_check');

  return {
    'repairs': repairs,
    'invoices': invoices,
    'repairs_with_invoice': repairsWithInvoice,
    'duplicate_repair_invoices': duplicateRepairInvoices,
    'orphan_invoices': orphanInvoices,
    'canonical_links': canonicalLinks,
    'missing_canonical_links': missingCanonicalLinks,
    'amount_mismatch_count': firstInt(amountMismatch),
    'amount_mismatch_abs_ils': number(amountMismatch.first['abs_diff']),
    'amount_mismatch_net_ils': number(amountMismatch.first['net_diff']),
    'repairs_without_invoice': noInvoice,
    'invoice_gl_coverage': invoiceGlCoverage,
    'p0_005_reclass_entries': p0005,
    'unbalanced_gl_entries': unbalanced,
    'integrity_ok':
        integrity.isNotEmpty && integrity.first.values.first.toString() == 'ok',
  };
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(dbPath).existsSync()) {
    stderr.writeln('P0.006 ERROR: DB not found at $dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(dbPath);

  try {
    final version = firstInt(await db.rawQuery('PRAGMA user_version'));
    if (version != 55) {
      throw StateError(
        'P0.006 refused: expected DB user_version 55, found $version.',
      );
    }

    final before = await snapshot(db);

    if (before['repairs'] != 114 ||
        before['invoices'] != 113 ||
        before['repairs_with_invoice'] != 113 ||
        before['duplicate_repair_invoices'] != 0 ||
        before['orphan_invoices'] != 0 ||
        before['amount_mismatch_count'] != 33 ||
        ((before['amount_mismatch_abs_ils'] as double) - 47150.0).abs() >
            0.01 ||
        ((before['amount_mismatch_net_ils'] as double) + 5050.0).abs() > 0.01 ||
        before['invoice_gl_coverage'] != 113 ||
        before['p0_005_reclass_entries'] != 24 ||
        before['unbalanced_gl_entries'] != 0 ||
        before['integrity_ok'] != true) {
      throw StateError(
        'P0.006 refused: live DB changed since audited preflight: $before',
      );
    }

    final noInvoice =
        before['repairs_without_invoice'] as List<Map<String, Object?>>;
    if (noInvoice.length != 1 ||
        noInvoice.first['id']?.toString() != repairWithoutInvoice ||
        (number(noInvoice.first['fileValue']) - 39600.0).abs() > 0.01) {
      throw StateError(
        'P0.006 refused: repair-without-invoice set changed: $noInvoice',
      );
    }

    stdout.writeln(
      'P0.006 preflight PASS: 114 repairs / 113 invoices / '
      '33 historical Repair-vs-Invoice amount differences.',
    );
    stdout.writeln(
      'P0.006 policy: historical posted invoice amounts will NOT be changed.',
    );

    if (!apply) {
      stdout.writeln('Audit only. Re-run with --apply to synchronize links.');
      return;
    }

    await db.transaction((txn) async {
      await txn.rawUpdate(r'''
        UPDATE repairs
        SET invoice_id = (
          SELECT i.id
          FROM invoices i
          WHERE i.repair_id=repairs.id
          LIMIT 1
        )
        WHERE EXISTS (
          SELECT 1 FROM invoices i WHERE i.repair_id=repairs.id
        )
      ''');

      // Legacy mirror only; no future code depends on it as truth.
      final info = await txn.rawQuery('PRAGMA table_info(repairs)');
      final hasLegacy = info.any((r) => r['name'] == 'invoiceId');
      if (hasLegacy) {
        await txn.rawUpdate(r'''
          UPDATE repairs
          SET invoiceId=invoice_id
          WHERE COALESCE(invoice_id,'') <> ''
        ''');
      }

      // Historical Repair != Invoice differences are preserved and explicitly
      // marked as not ledger-synchronized.
      await txn.rawUpdate(r'''
        UPDATE repairs
        SET isLedgerSynced=0
        WHERE id IN (
          SELECT r.id
          FROM repairs r
          JOIN invoices i ON i.repair_id=r.id
          WHERE ABS(COALESCE(r.fileValue,0)-COALESCE(i.total,0)) > 0.01
        )
      ''');

      await txn.execute(r'''
        CREATE UNIQUE INDEX IF NOT EXISTS uq_invoices_repair_id
        ON invoices(repair_id)
        WHERE repair_id IS NOT NULL AND TRIM(repair_id) <> ''
      ''');
    });

    final after = await snapshot(db);

    final p0004Link = await db.rawQuery(
      '''
      SELECT r.invoice_id, i.id AS invoice_id_from_invoice
      FROM repairs r
      JOIN invoices i ON i.repair_id=r.id
      WHERE r.id=?
      ''',
      [p0004Repair],
    );

    final mismatchStillPreserved = after['amount_mismatch_count'] == 33 &&
        ((after['amount_mismatch_abs_ils'] as double) - 47150.0).abs() <=
            0.01 &&
        ((after['amount_mismatch_net_ils'] as double) + 5050.0).abs() <= 0.01;

    final mismatchUnsynced = firstInt(
      await db.rawQuery(r'''
        SELECT COUNT(*)
        FROM repairs r
        JOIN invoices i ON i.repair_id=r.id
        WHERE ABS(COALESCE(r.fileValue,0)-COALESCE(i.total,0)) > 0.01
          AND COALESCE(r.isLedgerSynced,0)=0
      '''),
    );

    if (after['canonical_links'] != 113 ||
        after['missing_canonical_links'] != 0 ||
        after['duplicate_repair_invoices'] != 0 ||
        after['orphan_invoices'] != 0 ||
        after['invoice_gl_coverage'] != 113 ||
        mismatchStillPreserved != true ||
        mismatchUnsynced != 33 ||
        after['unbalanced_gl_entries'] != 0 ||
        after['integrity_ok'] != true ||
        p0004Link.length != 1 ||
        p0004Link.first['invoice_id']?.toString() !=
            p0004Link.first['invoice_id_from_invoice']?.toString()) {
      throw StateError(
        'P0.006 post-validation failed: after=$after '
        'mismatchUnsynced=$mismatchUnsynced p0004Link=$p0004Link',
      );
    }

    await report({
      'status': 'PASS',
      'canonical_relationship': 'invoices.repair_id',
      'repair_invoice_cache': 'repairs.invoice_id',
      'repairs': 114,
      'invoices': 113,
      'canonical_links': 113,
      'repairs_without_invoice': 1,
      'repairs_without_invoice_id': repairWithoutInvoice,
      'historical_amount_mismatches_preserved': 33,
      'historical_amount_mismatch_abs_ils': 47150.0,
      'historical_amount_mismatch_net_ils': -5050.0,
      'mismatch_repairs_marked_isLedgerSynced_false': 33,
      'invoice_gl_coverage': 113,
      'duplicate_invoices_per_repair': 0,
      'unbalanced_gl_entries': 0,
      'integrity_check': 'ok',
    });

    stdout.writeln(
      'P0.006 DATA LINK REPAIR PASS: 113/113 invoiced repairs linked.',
    );
    stdout.writeln(
      'P0.006 historical amount differences preserved: '
      '33 repairs / 47,150.00 ILS absolute difference.',
    );
    stdout.writeln(
      'P0.006 one intentional repair without invoice preserved: 39,600.00 ILS.',
    );
    stdout.writeln('P0.006 unique one-invoice-per-repair constraint PASS.');
    stdout.writeln('P0.006 GL coverage PASS: 113/113 invoices.');
    stdout.writeln('P0.006 GL balance validation PASS.');
    stdout.writeln('P0.006 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
