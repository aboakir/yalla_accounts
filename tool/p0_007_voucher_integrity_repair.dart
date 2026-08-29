import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const dbPath = r'D:/YallaAccounts/yalla_accounts.db';

const invalidSettlementId = '5f7cfa02-19bc-4223-a55c-cb656f36acbe';
const invalidSettlementVoucherId = '31082280-a34c-45f0-ba36-f81ab594db21';
const invalidSettlementAmount = 400.0;

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

Future<void> writeReport(Map<String, Object?> body) async {
  final home = Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return;

  final file = File(
    '$home${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}Yalla_P0_007_RESULT.json',
  );

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(body),
    flush: true,
  );
}

Future<Map<String, Object?>> snapshot(Database db) async {
  final voucherCount = firstInt(
    await db.rawQuery('SELECT COUNT(*) FROM vouchers'),
  );

  final voucherAmountRow = await db.rawQuery(
    'SELECT COALESCE(SUM(amount),0) AS s FROM vouchers',
  );
  final voucherAmount = asDouble(voucherAmountRow.first['s']);

  final voucherGlCount = firstInt(
    await db.rawQuery(
      "SELECT COUNT(*) FROM gl_entries WHERE source='VOUCHER'",
    ),
  );

  final voucherCacheMismatch = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM vouchers v
      WHERE COALESCE(v.is_posted,0) <>
        CASE WHEN EXISTS (
          SELECT 1 FROM gl_entries e
          WHERE e.source='VOUCHER' AND e.source_id=v.id
        ) THEN 1 ELSE 0 END
      OR COALESCE(v.gl_entry_id,0) <>
        COALESCE((
          SELECT e.id FROM gl_entries e
          WHERE e.source='VOUCHER' AND e.source_id=v.id
          LIMIT 1
        ),0)
    '''),
  );

  final duplicateVoucherGl = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT source_id
        FROM gl_entries
        WHERE source='VOUCHER'
        GROUP BY source_id
        HAVING COUNT(*) > 1
      )
    '''),
  );

  final orphanVoucherGl = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM gl_entries e
      LEFT JOIN vouchers v ON v.id=e.source_id
      WHERE e.source='VOUCHER' AND v.id IS NULL
    '''),
  );

  final voucherAmountMismatch = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT
          v.id,
          v.amount,
          SUM(l.debit) AS d,
          SUM(l.credit) AS c
        FROM vouchers v
        JOIN gl_entries e
          ON e.source='VOUCHER' AND e.source_id=v.id
        JOIN gl_lines l ON l.entry_id=e.id
        GROUP BY v.id
        HAVING ABS(d-c) > 0.01
          OR ABS(d-v.amount) > 0.01
          OR ABS(c-v.amount) > 0.01
      )
    '''),
  );

  final receiptCount = firstInt(
    await db.rawQuery(
      'SELECT COUNT(*) FROM payments WHERE isIncome=1',
    ),
  );

  final receiptAmountRow = await db.rawQuery(
    'SELECT COALESCE(SUM(amount),0) AS s '
    'FROM payments WHERE isIncome=1',
  );
  final receiptAmount = asDouble(receiptAmountRow.first['s']);

  final receiptGlCount = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM payments p
      WHERE p.isIncome=1
        AND EXISTS (
          SELECT 1 FROM gl_entries e
          WHERE e.source='PAYMENT' AND e.source_id=p.id
        )
    '''),
  );

  final receiptCacheMismatch = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM payments p
      WHERE p.isIncome=1
        AND COALESCE(p.gl_entry_id,0) <>
          COALESCE((
            SELECT e.id FROM gl_entries e
            WHERE e.source='PAYMENT' AND e.source_id=p.id
            LIMIT 1
          ),0)
    '''),
  );

  final receiptAmountMismatch = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM (
        SELECT
          p.id,
          p.amount,
          SUM(l.debit) AS d,
          SUM(l.credit) AS c,
          SUM(CASE
            WHEN a.code IN ('1000','1010','1020')
            THEN l.debit-l.credit ELSE 0 END
          ) AS liquid_effect,
          SUM(CASE
            WHEN a.code LIKE '1200.C%'
            THEN l.credit-l.debit ELSE 0 END
          ) AS ar_effect
        FROM payments p
        JOIN gl_entries e
          ON e.source='PAYMENT' AND e.source_id=p.id
        JOIN gl_lines l ON l.entry_id=e.id
        JOIN accounts a ON a.id=l.account_id
        WHERE p.isIncome=1
        GROUP BY p.id
        HAVING ABS(d-c) > 0.01
          OR ABS(liquid_effect-p.amount) > 0.01
          OR ABS(ar_effect-p.amount) > 0.01
      )
    '''),
  );

  final generalReceiptCount = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM payments
      WHERE isIncome=1
        AND COALESCE(repair_id,'')=''
        AND COALESCE(relatedRepairId,'')=''
    '''),
  );

  final settlementCount = firstInt(
    await db.rawQuery('SELECT COUNT(*) FROM invoice_settlements'),
  );

  final orphanSettlementCount = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM invoice_settlements s
      LEFT JOIN vouchers v ON v.id=s.voucher_id
      LEFT JOIN purchase_invoices i
        ON CAST(i.id AS TEXT)=CAST(s.invoice_id AS TEXT)
      WHERE v.id IS NULL OR i.id IS NULL
    '''),
  );

  final incompleteChequeVoucherCount = firstInt(
    await db.rawQuery(r'''
      SELECT COUNT(*)
      FROM vouchers
      WHERE LOWER(method)='cheque'
        AND COALESCE(cheque_id,'')=''
    '''),
  );

  final chequeCount = firstInt(
    await db.rawQuery('SELECT COUNT(*) FROM cheques'),
  );

  final glLineRow = await db.rawQuery(r'''
    SELECT
      COUNT(*) AS c,
      COALESCE(SUM(debit),0) AS d,
      COALESCE(SUM(credit),0) AS cr
    FROM gl_lines
  ''');

  final unbalanced = firstInt(
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

  return {
    'voucher_count': voucherCount,
    'voucher_amount_ils': voucherAmount,
    'voucher_gl_count': voucherGlCount,
    'voucher_cache_mismatch': voucherCacheMismatch,
    'duplicate_voucher_gl': duplicateVoucherGl,
    'orphan_voucher_gl': orphanVoucherGl,
    'voucher_amount_mismatch': voucherAmountMismatch,
    'receipt_count': receiptCount,
    'receipt_amount_ils': receiptAmount,
    'receipt_gl_count': receiptGlCount,
    'receipt_cache_mismatch': receiptCacheMismatch,
    'receipt_amount_mismatch': receiptAmountMismatch,
    'general_receipt_count': generalReceiptCount,
    'settlement_count': settlementCount,
    'orphan_settlement_count': orphanSettlementCount,
    'incomplete_cheque_voucher_count': incompleteChequeVoucherCount,
    'cheque_count': chequeCount,
    'gl_line_count': asInt(glLineRow.first['c']),
    'gl_debit_total': asDouble(glLineRow.first['d']),
    'gl_credit_total': asDouble(glLineRow.first['cr']),
    'unbalanced_gl_entries': unbalanced,
    'integrity_ok':
        integrity.isNotEmpty && integrity.first.values.first.toString() == 'ok',
  };
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(dbPath).existsSync()) {
    stderr.writeln('P0.007 ERROR: DB not found at $dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(dbPath);

  try {
    final version = firstInt(
      await db.rawQuery('PRAGMA user_version'),
    );

    if (version != 55) {
      throw StateError(
        'P0.007 refused: expected DB user_version 55, found $version.',
      );
    }

    final before = await snapshot(db);

    if (before['voucher_count'] != 55 ||
        ((before['voucher_amount_ils'] as double) - 61202.98).abs() > 0.01 ||
        before['voucher_gl_count'] != 55 ||
        before['voucher_cache_mismatch'] != 0 ||
        before['duplicate_voucher_gl'] != 0 ||
        before['orphan_voucher_gl'] != 0 ||
        before['voucher_amount_mismatch'] != 0 ||
        before['receipt_count'] != 37 ||
        ((before['receipt_amount_ils'] as double) - 85185.0).abs() > 0.01 ||
        before['receipt_gl_count'] != 37 ||
        before['receipt_cache_mismatch'] != 0 ||
        before['receipt_amount_mismatch'] != 0 ||
        before['general_receipt_count'] != 0 ||
        before['settlement_count'] != 1 ||
        before['orphan_settlement_count'] != 1 ||
        before['incomplete_cheque_voucher_count'] != 1 ||
        before['cheque_count'] != 0 ||
        before['unbalanced_gl_entries'] != 0 ||
        before['integrity_ok'] != true) {
      throw StateError(
        'P0.007 refused: live DB changed since audited preflight: $before',
      );
    }

    final invalid = await db.query(
      'invoice_settlements',
      where: 'id=?',
      whereArgs: [invalidSettlementId],
      limit: 1,
    );

    if (invalid.length != 1 ||
        asInt(invalid.first['supplier_id']) != 8 ||
        invalid.first['voucher_id']?.toString() != invalidSettlementVoucherId ||
        asInt(invalid.first['invoice_id']) != 0 ||
        (asDouble(invalid.first['amount_applied']) - invalidSettlementAmount)
                .abs() >
            0.01) {
      throw StateError(
        'P0.007 refused: audited invalid settlement row changed: $invalid',
      );
    }

    stdout.writeln(
      'P0.007 preflight PASS: 55 payment vouchers and 37 receipts '
      'have valid, balanced GL.',
    );
    stdout.writeln(
      'P0.007 found one invalid operational settlement helper row '
      '(400.00 ILS, invoice_id=0, orphan voucher).',
    );
    stdout.writeln(
      'P0.007 cheque baseline preserved for P0.008: '
      '1 incomplete 2,000 ILS cheque voucher / 0 cheque records.',
    );

    if (!apply) return;

    final glLineCountBefore = before['gl_line_count'];
    final glDebitBefore = before['gl_debit_total'];
    final glCreditBefore = before['gl_credit_total'];

    await db.transaction((txn) async {
      final deleted = await txn.delete(
        'invoice_settlements',
        where: 'id=?',
        whereArgs: [invalidSettlementId],
      );

      if (deleted != 1) {
        throw StateError(
          'P0.007 expected to remove exactly one invalid settlement row.',
        );
      }

      await txn.execute(r'''
        CREATE UNIQUE INDEX IF NOT EXISTS
          uq_settlements_voucher_invoice
        ON invoice_settlements(voucher_id, invoice_id)
      ''');
    });

    final after = await snapshot(db);

    if (after['voucher_count'] != 55 ||
        after['voucher_gl_count'] != 55 ||
        after['voucher_cache_mismatch'] != 0 ||
        after['duplicate_voucher_gl'] != 0 ||
        after['orphan_voucher_gl'] != 0 ||
        after['voucher_amount_mismatch'] != 0 ||
        after['receipt_count'] != 37 ||
        after['receipt_gl_count'] != 37 ||
        after['receipt_cache_mismatch'] != 0 ||
        after['receipt_amount_mismatch'] != 0 ||
        after['settlement_count'] != 0 ||
        after['orphan_settlement_count'] != 0 ||
        after['incomplete_cheque_voucher_count'] != 1 ||
        after['cheque_count'] != 0 ||
        after['gl_line_count'] != glLineCountBefore ||
        ((after['gl_debit_total'] as double) - (glDebitBefore as double))
                .abs() >
            0.001 ||
        ((after['gl_credit_total'] as double) - (glCreditBefore as double))
                .abs() >
            0.001 ||
        after['unbalanced_gl_entries'] != 0 ||
        after['integrity_ok'] != true) {
      throw StateError(
        'P0.007 post-validation failed: before=$before after=$after',
      );
    }

    await writeReport({
      'status': 'PASS',
      'payment_vouchers': 55,
      'payment_vouchers_gl': 55,
      'payment_voucher_amount_ils': 61202.98,
      'receipt_vouchers': 37,
      'receipt_vouchers_gl': 37,
      'receipt_amount_ils': 85185.0,
      'voucher_cache_mismatch': 0,
      'receipt_cache_mismatch': 0,
      'duplicate_voucher_gl': 0,
      'orphan_voucher_gl': 0,
      'invalid_settlement_rows_removed': 1,
      'invalid_settlement_amount_ils': 400.0,
      'historical_gl_changed': false,
      'incomplete_cheque_vouchers_preserved_for_p0_008': 1,
      'cheque_records': 0,
      'unbalanced_gl_entries': 0,
      'integrity_check': 'ok',
    });

    stdout.writeln(
      'P0.007 DATA REPAIR PASS: invalid settlement helper row removed.',
    );
    stdout.writeln('P0.007 voucher GL coverage PASS: 55/55.');
    stdout.writeln('P0.007 receipt GL coverage PASS: 37/37.');
    stdout.writeln('P0.007 GL financial totals unchanged: PASS.');
    stdout.writeln(
      'P0.007 cheque defect intentionally preserved for P0.008: PASS.',
    );
    stdout.writeln('P0.007 GL balance validation PASS.');
    stdout.writeln('P0.007 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
