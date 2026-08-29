import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbPath = r'D:/YallaAccounts/yalla_accounts.db';
const _missingInvoiceId = 'db2a8a09-a868-40f4-bfe4-36f3732953b2';

int _firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final v = rows.first.values.first;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

Future<void> _report(Map<String, Object?> data) async {
  final home = Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return;
  final file = File(
    '$home${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}Yalla_P0_003_POSTING_STATUS_RESULT.json',
  );
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(data),
    flush: true,
  );
}

Future<Map<String, Object?>> _validate(Database db) async {
  final invoiceCount =
      _firstInt(await db.rawQuery('SELECT COUNT(*) FROM invoices'));

  final invoicePosted = _firstInt(await db.rawQuery(r'''
    SELECT COUNT(*)
    FROM invoices i
    WHERE EXISTS (
      SELECT 1 FROM gl_entries e
      WHERE e.source='INVOICE' AND e.source_id=i.id
    )
  '''));

  final invoiceCacheMismatch = _firstInt(await db.rawQuery(r'''
    SELECT COUNT(*)
    FROM invoices i
    WHERE
      COALESCE(i.post_to_gl,0) <>
      CASE WHEN EXISTS (
        SELECT 1 FROM gl_entries e
        WHERE e.source='INVOICE' AND e.source_id=i.id
      ) THEN 1 ELSE 0 END
      OR
      COALESCE(i.gl_entry_id,0) <>
      COALESCE((
        SELECT e.id FROM gl_entries e
        WHERE e.source='INVOICE' AND e.source_id=i.id
        ORDER BY e.id DESC LIMIT 1
      ),0)
  '''));

  final missingInvoices = await db.rawQuery(r'''
    SELECT id,total
    FROM invoices i
    WHERE NOT EXISTS (
      SELECT 1 FROM gl_entries e
      WHERE e.source='INVOICE' AND e.source_id=i.id
    )
    ORDER BY id
  ''');

  final voucherCount =
      _firstInt(await db.rawQuery('SELECT COUNT(*) FROM vouchers'));

  final voucherPosted = _firstInt(await db.rawQuery(r'''
    SELECT COUNT(*)
    FROM vouchers v
    WHERE EXISTS (
      SELECT 1 FROM gl_entries e
      WHERE e.source='VOUCHER' AND e.source_id=v.id
    )
  '''));

  final voucherCacheMismatch = _firstInt(await db.rawQuery(r'''
    SELECT COUNT(*)
    FROM vouchers v
    WHERE
      COALESCE(v.is_posted,0) <>
      CASE WHEN EXISTS (
        SELECT 1 FROM gl_entries e
        WHERE e.source='VOUCHER' AND e.source_id=v.id
      ) THEN 1 ELSE 0 END
      OR
      COALESCE(v.gl_entry_id,0) <>
      COALESCE((
        SELECT e.id FROM gl_entries e
        WHERE e.source='VOUCHER' AND e.source_id=v.id
        ORDER BY e.id DESC LIMIT 1
      ),0)
  '''));

  final receiptCount = _firstInt(await db.rawQuery(
    'SELECT COUNT(*) FROM payments WHERE isIncome=1',
  ));

  final receiptPosted = _firstInt(await db.rawQuery(r'''
    SELECT COUNT(*)
    FROM payments p
    WHERE p.isIncome=1
      AND EXISTS (
        SELECT 1 FROM gl_entries e
        WHERE e.source='PAYMENT' AND e.source_id=p.id
      )
  '''));

  final receiptCacheMismatch = _firstInt(await db.rawQuery(r'''
    SELECT COUNT(*)
    FROM payments p
    WHERE p.isIncome=1
      AND COALESCE(p.gl_entry_id,0) <>
      COALESCE((
        SELECT e.id FROM gl_entries e
        WHERE e.source='PAYMENT' AND e.source_id=p.id
        ORDER BY e.id DESC LIMIT 1
      ),0)
  '''));

  final unbalanced = _firstInt(await db.rawQuery(r'''
    SELECT COUNT(*)
    FROM (
      SELECT entry_id, SUM(debit-credit) AS diff
      FROM gl_lines
      GROUP BY entry_id
      HAVING ABS(diff) > 0.01
    )
  '''));

  final integrity = await db.rawQuery('PRAGMA integrity_check');
  final integrityOk =
      integrity.isNotEmpty && integrity.first.values.first.toString() == 'ok';

  return {
    'invoice_count': invoiceCount,
    'invoice_posted_from_gl': invoicePosted,
    'invoice_cache_mismatch': invoiceCacheMismatch,
    'missing_invoices': missingInvoices,
    'voucher_count': voucherCount,
    'voucher_posted_from_gl': voucherPosted,
    'voucher_cache_mismatch': voucherCacheMismatch,
    'receipt_count': receiptCount,
    'receipt_posted_from_gl': receiptPosted,
    'receipt_cache_mismatch': receiptCacheMismatch,
    'unbalanced_gl_entries': unbalanced,
    'integrity_ok': integrityOk,
  };
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(_dbPath).existsSync()) {
    stderr.writeln('P0.003 ERROR: database not found at $_dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(_dbPath);

  try {
    final version = _firstInt(await db.rawQuery('PRAGMA user_version'));
    if (version != 55) {
      throw StateError(
        'P0.003 refused: expected DB user_version 55, found $version.',
      );
    }

    final baseline = await _validate(db);

    if (baseline['invoice_count'] != 113 ||
        baseline['invoice_posted_from_gl'] != 112 ||
        baseline['voucher_count'] != 55 ||
        baseline['voucher_posted_from_gl'] != 55 ||
        baseline['receipt_count'] != 37 ||
        baseline['receipt_posted_from_gl'] != 37 ||
        baseline['unbalanced_gl_entries'] != 0 ||
        baseline['integrity_ok'] != true) {
      throw StateError(
        'P0.003 refused: live DB no longer matches audited baseline: $baseline',
      );
    }

    final missing = baseline['missing_invoices'] as List<Map<String, Object?>>;
    if (missing.length != 1 ||
        missing.first['id']?.toString() != _missingInvoiceId) {
      throw StateError(
        'P0.003 refused: missing-invoice set changed: $missing',
      );
    }

    stdout.writeln(
      'P0.003 preflight PASS: invoices 112/113 posted from actual GL; '
      'vouchers 55/55; receipts 37/37.',
    );

    if (!apply) {
      stdout.writeln('Audit only. Re-run with --apply to synchronize caches.');
      return;
    }

    await db.transaction((txn) async {
      await txn.rawUpdate(r'''
        UPDATE invoices
        SET
          gl_entry_id = (
            SELECT e.id
            FROM gl_entries e
            WHERE e.source='INVOICE'
              AND e.source_id=invoices.id
            ORDER BY e.id DESC
            LIMIT 1
          ),
          post_to_gl = CASE
            WHEN EXISTS (
              SELECT 1
              FROM gl_entries e
              WHERE e.source='INVOICE'
                AND e.source_id=invoices.id
            ) THEN 1 ELSE 0 END,
          updated_at = CURRENT_TIMESTAMP
      ''');

      await txn.rawUpdate(r'''
        UPDATE vouchers
        SET
          gl_entry_id = (
            SELECT e.id
            FROM gl_entries e
            WHERE e.source='VOUCHER'
              AND e.source_id=vouchers.id
            ORDER BY e.id DESC
            LIMIT 1
          ),
          is_posted = CASE
            WHEN EXISTS (
              SELECT 1
              FROM gl_entries e
              WHERE e.source='VOUCHER'
                AND e.source_id=vouchers.id
            ) THEN 1 ELSE 0 END,
          posted_at = CASE
            WHEN EXISTS (
              SELECT 1
              FROM gl_entries e
              WHERE e.source='VOUCHER'
                AND e.source_id=vouchers.id
            )
            THEN COALESCE(
              posted_at,
              (
                SELECT COALESCE(e.created_at,e.date)
                FROM gl_entries e
                WHERE e.source='VOUCHER'
                  AND e.source_id=vouchers.id
                ORDER BY e.id DESC
                LIMIT 1
              )
            )
            ELSE posted_at
          END,
          updated_at = CURRENT_TIMESTAMP
      ''');

      await txn.rawUpdate(r'''
        UPDATE payments
        SET gl_entry_id = (
          SELECT e.id
          FROM gl_entries e
          WHERE e.source='PAYMENT'
            AND e.source_id=payments.id
          ORDER BY e.id DESC
          LIMIT 1
        )
        WHERE isIncome=1
      ''');
    });

    final after = await _validate(db);
    final missingAfter =
        after['missing_invoices'] as List<Map<String, Object?>>;

    if (after['invoice_cache_mismatch'] != 0 ||
        after['voucher_cache_mismatch'] != 0 ||
        after['receipt_cache_mismatch'] != 0 ||
        after['invoice_posted_from_gl'] != 112 ||
        after['voucher_posted_from_gl'] != 55 ||
        after['receipt_posted_from_gl'] != 37 ||
        after['unbalanced_gl_entries'] != 0 ||
        after['integrity_ok'] != true ||
        missingAfter.length != 1 ||
        missingAfter.first['id']?.toString() != _missingInvoiceId) {
      throw StateError(
        'P0.003 post-sync validation failed: $after',
      );
    }

    await _report({
      'status': 'PASS',
      'posting_truth': 'gl_entries(source, source_id)',
      'invoice_total': 113,
      'invoice_posted': 112,
      'invoice_unposted': 1,
      'invoice_unposted_id': _missingInvoiceId,
      'voucher_total': 55,
      'voucher_posted': 55,
      'receipt_total': 37,
      'receipt_posted': 37,
      'invoice_cache_mismatch': 0,
      'voucher_cache_mismatch': 0,
      'receipt_cache_mismatch': 0,
      'unbalanced_gl_entries': 0,
      'integrity_check': 'ok',
    });

    stdout.writeln(
      'P0.003 DATA SYNC PASS: compatibility posting fields synchronized '
      'from actual GL.',
    );
    stdout.writeln(
      'P0.003 invoice status PASS: 112 posted / 1 truly unposted.',
    );
    stdout.writeln('P0.003 voucher status PASS: 55/55 posted.');
    stdout.writeln('P0.003 receipt status PASS: 37/37 posted.');
    stdout.writeln('P0.003 GL validation PASS.');
    stdout.writeln('P0.003 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
