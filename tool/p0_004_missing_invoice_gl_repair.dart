import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbPath = r'D:/YallaAccounts/yalla_accounts.db';

const _invoiceId = 'db2a8a09-a868-40f4-bfe4-36f3732953b2';
const _repairId = '89fb8c7a-ef8a-462a-8aaf-6cb42d717974';
const _clientId = 3;
const _amount = 2200.0;
const _arAccountId = 21;
const _revenueAccountId = 13;

double _double(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int _firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  return _int(rows.first.values.first);
}

Future<void> _writeReport(Map<String, Object?> data) async {
  final home = Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return;

  final file = File(
    '$home${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}Yalla_P0_004_RESULT.json',
  );

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(data),
    flush: true,
  );
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');

  sqfliteFfiInit();

  if (!File(_dbPath).existsSync()) {
    stderr.writeln('P0.004 ERROR: DB not found at $_dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(_dbPath);

  try {
    final version = _firstInt(await db.rawQuery('PRAGMA user_version'));
    if (version != 55) {
      throw StateError(
        'P0.004 refused: expected DB user_version 55, found $version.',
      );
    }

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first.toString() != 'ok') {
      throw StateError('P0.004 refused: DB integrity_check is not OK.');
    }

    final inv = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [_invoiceId],
      limit: 1,
    );

    if (inv.length != 1) {
      throw StateError(
        'P0.004 refused: audited invoice not found exactly once.',
      );
    }

    final row = inv.first;
    final total = _double(row['total']);
    final vat = _double(row['vat']);
    final vatAmount = _double(row['vat_amount']);

    if (row['repair_id']?.toString() != _repairId ||
        _int(row['client_id']) != _clientId ||
        (total - _amount).abs() > 0.01 ||
        vat.abs() > 0.01 ||
        vatAmount.abs() > 0.01) {
      throw StateError(
        'P0.004 refused: invoice fields changed since preflight: $row',
      );
    }

    final repair = await db.query(
      'repairs',
      columns: ['id', 'client_id', 'fileValue'],
      where: 'id = ?',
      whereArgs: [_repairId],
      limit: 1,
    );

    if (repair.length != 1 ||
        _int(repair.first['client_id']) != _clientId ||
        (_double(repair.first['fileValue']) - _amount).abs() > 0.01) {
      throw StateError(
        'P0.004 refused: repair/client/value no longer matches audit.',
      );
    }

    final ar = await db.query(
      'accounts',
      columns: ['id', 'code'],
      where: 'id = ?',
      whereArgs: [_arAccountId],
      limit: 1,
    );

    final revenue = await db.query(
      'accounts',
      columns: ['id', 'code'],
      where: 'id = ?',
      whereArgs: [_revenueAccountId],
      limit: 1,
    );

    if (ar.length != 1 ||
        ar.first['code']?.toString() != '1200.C3' ||
        revenue.length != 1 ||
        revenue.first['code']?.toString() != '4000') {
      throw StateError(
        'P0.004 refused: audited AR/revenue accounts changed.',
      );
    }

    final existing = await db.query(
      'gl_entries',
      where: 'source = ? AND source_id = ?',
      whereArgs: ['INVOICE', _invoiceId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final entryId = _int(existing.first['id']);

      await db.update(
        'invoices',
        {
          'gl_entry_id': entryId,
          'post_to_gl': 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [_invoiceId],
      );

      stdout.writeln(
        'P0.004: INVOICE GL already exists; cache fields synchronized only.',
      );
    } else {
      final linkedLines = _firstInt(
        await db.rawQuery(
          '''
          SELECT COUNT(*)
          FROM gl_lines
          WHERE invoice_id = ? OR repair_id = ?
          ''',
          [_invoiceId, _repairId],
        ),
      );

      if (linkedLines != 0) {
        throw StateError(
          'P0.004 refused: unexpected partial GL lines reference '
          'the audited invoice/repair.',
        );
      }

      final relatedPayments = _firstInt(
        await db.rawQuery(
          '''
          SELECT COUNT(*)
          FROM payments
          WHERE invoice_id = ? OR repair_id = ?
          ''',
          [_invoiceId, _repairId],
        ),
      );

      if (relatedPayments != 0) {
        throw StateError(
          'P0.004 refused: audited invoice now has payment activity.',
        );
      }

      if (!apply) {
        stdout.writeln(
          'P0.004 preflight PASS: exact 2,200.00 ILS invoice is safe to post.',
        );
        return;
      }

      final now = DateTime.now().toIso8601String();
      final date = row['date']?.toString() ?? now;

      await db.transaction((txn) async {
        final entryId = await txn.insert(
          'gl_entries',
          {
            'date': date,
            'ref': _invoiceId,
            'source': 'INVOICE',
            'source_id': _invoiceId,
            'note': 'P0.004 historical missing invoice GL repair',
            'created_at': now,
            'updated_at': now,
          },
        );

        await txn.insert(
          'gl_lines',
          {
            'entry_id': entryId,
            'account_id': _arAccountId,
            'debit': _amount,
            'credit': 0.0,
            'party_type': 'CLIENT',
            'party_id': _clientId.toString(),
            'invoice_id': _invoiceId,
            'repair_id': _repairId,
            'created_at': now,
          },
        );

        await txn.insert(
          'gl_lines',
          {
            'entry_id': entryId,
            'account_id': _revenueAccountId,
            'debit': 0.0,
            'credit': _amount,
            'party_type': null,
            'party_id': null,
            'invoice_id': _invoiceId,
            'repair_id': _repairId,
            'created_at': now,
          },
        );

        await txn.update(
          'invoices',
          {
            'gl_entry_id': entryId,
            'post_to_gl': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [_invoiceId],
        );
      });
    }

    final invoicePosting = await db.rawQuery(
      '''
      SELECT
        e.id,
        SUM(CASE WHEN a.code='1200.C3'
          THEN l.debit-l.credit ELSE 0 END) AS ar_effect,
        SUM(CASE WHEN a.code='4000'
          THEN l.credit-l.debit ELSE 0 END) AS revenue_effect,
        COUNT(l.id) AS line_count
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      JOIN accounts a ON a.id=l.account_id
      WHERE e.source='INVOICE' AND e.source_id=?
      GROUP BY e.id
      ''',
      [_invoiceId],
    );

    if (invoicePosting.length != 1 ||
        (_double(invoicePosting.first['ar_effect']) - _amount).abs() > 0.01 ||
        (_double(invoicePosting.first['revenue_effect']) - _amount).abs() >
            0.01 ||
        _int(invoicePosting.first['line_count']) != 2) {
      throw StateError(
        'P0.004 post-validation failed for invoice GL: $invoicePosting',
      );
    }

    final missingInvoices = _firstInt(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM invoices i
        WHERE NOT EXISTS (
          SELECT 1
          FROM gl_entries e
          WHERE e.source='INVOICE' AND e.source_id=i.id
        )
        ''',
      ),
    );

    final invoiceCacheMismatch = _firstInt(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM invoices i
        WHERE COALESCE(i.post_to_gl,0) <>
          CASE WHEN EXISTS (
            SELECT 1 FROM gl_entries e
            WHERE e.source='INVOICE' AND e.source_id=i.id
          ) THEN 1 ELSE 0 END
          OR COALESCE(i.gl_entry_id,0) <>
          COALESCE((
            SELECT e.id FROM gl_entries e
            WHERE e.source='INVOICE' AND e.source_id=i.id
            ORDER BY e.id DESC LIMIT 1
          ),0)
        ''',
      ),
    );

    final duplicateInvoiceHeaders = _firstInt(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM (
          SELECT source_id
          FROM gl_entries
          WHERE source='INVOICE'
          GROUP BY source_id
          HAVING COUNT(*) > 1
        )
        ''',
      ),
    );

    final unbalanced = _firstInt(
      await db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM (
          SELECT entry_id, SUM(debit-credit) diff
          FROM gl_lines
          GROUP BY entry_id
          HAVING ABS(diff) > 0.01
        )
        ''',
      ),
    );

    final integrityAfter = await db.rawQuery('PRAGMA integrity_check');
    final integrityOk = integrityAfter.isNotEmpty &&
        integrityAfter.first.values.first.toString() == 'ok';

    if (missingInvoices != 0 ||
        invoiceCacheMismatch != 0 ||
        duplicateInvoiceHeaders != 0 ||
        unbalanced != 0 ||
        !integrityOk) {
      throw StateError(
        'P0.004 global validation failed: '
        'missing=$missingInvoices '
        'cacheMismatch=$invoiceCacheMismatch '
        'duplicates=$duplicateInvoiceHeaders '
        'unbalanced=$unbalanced '
        'integrity=$integrityOk',
      );
    }

    await _writeReport({
      'status': 'PASS',
      'invoice_id': _invoiceId,
      'repair_id': _repairId,
      'client_id': _clientId,
      'amount_ils': _amount,
      'ar_account': '1200.C3',
      'revenue_account': '4000',
      'missing_invoice_gl_after': 0,
      'invoice_cache_mismatch_after': 0,
      'duplicate_invoice_headers_after': 0,
      'unbalanced_gl_entries': 0,
      'integrity_check': 'ok',
    });

    stdout.writeln(
      'P0.004 DATA REPAIR PASS: missing 2,200.00 ILS invoice posted.',
    );
    stdout.writeln(
      'P0.004 invoice coverage PASS: 113/113 invoices have GL.',
    );
    stdout.writeln('P0.004 duplicate INVOICE header check PASS: 0.');
    stdout.writeln('P0.004 GL balance validation PASS.');
    stdout.writeln('P0.004 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
