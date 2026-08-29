import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const dbPath = r'D:/YallaAccounts/yalla_accounts.db';

const voucherId = 'c230bb4e-daa0-4859-bbe7-ef0d79fc120d';
const voucherNumber = 'P-0009';
const supplierId = 2;
const amount = 2000.0;
const originalVoucherGlId = 71;
const originalApReclassGlId = 429;

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

Future<void> ensureColumn(
  DatabaseExecutor db,
  String table,
  String column,
  String type,
) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  if (!info.any((row) => row['name'] == column)) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }
}

Future<void> ensureSchema(DatabaseExecutor db) async {
  final columns = <String, String>{
    'uuid': 'TEXT',
    'cheque_no': 'TEXT',
    'cheque_type': "TEXT NOT NULL DEFAULT 'incoming'",
    'drawer_name': 'TEXT',
    'bank_name': 'TEXT',
    'bank_branch': 'TEXT',
    'currency': "TEXT NOT NULL DEFAULT 'ILS'",
    'issue_date': 'TEXT',
    'source_type': 'TEXT',
    'source_id': 'TEXT',
    'supplier_pid': 'TEXT',
    'recipient_type': 'TEXT',
    'recipient_id': 'TEXT',
    'recipient_name': 'TEXT',
    'linked_repair_ids': 'TEXT',
    'gl_entry_id': 'INTEGER',
    'origin_cheque_id': 'TEXT',
    'is_endorsed': 'INTEGER NOT NULL DEFAULT 0',
    'endorsed_at': 'TEXT',
    'last_endorser_name': 'TEXT',
    'auto_return_date': 'TEXT',
    'return_reason': 'TEXT',
    'is_legacy_incomplete': 'INTEGER NOT NULL DEFAULT 0',
    'created_at': 'TEXT',
    'updated_at': 'TEXT',
  };

  for (final entry in columns.entries) {
    await ensureColumn(db, 'cheques', entry.key, entry.value);
  }

  await db.execute(r'''
    CREATE TABLE IF NOT EXISTS cheque_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cheque_id INTEGER NOT NULL,
      event_type TEXT NOT NULL,
      from_status TEXT,
      to_status TEXT,
      event_date TEXT NOT NULL,
      gl_entry_id INTEGER,
      note TEXT,
      created_at TEXT NOT NULL
    )
  ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cheques_status ON cheques(status)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cheques_due_date ON cheques(due_date)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cheques_client ON cheques(client_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cheques_supplier_pid '
    'ON cheques(supplier_pid)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cheques_source '
    'ON cheques(source_type, source_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cheque_events_cheque '
    'ON cheque_events(cheque_id, id)',
  );
  await db.execute(r'''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_cheques_uuid
    ON cheques(uuid)
    WHERE uuid IS NOT NULL AND TRIM(uuid) <> ''
  ''');
  await db.execute(r'''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_cheques_source
    ON cheques(source_type, source_id)
    WHERE source_type IS NOT NULL
      AND TRIM(source_type) <> ''
      AND source_id IS NOT NULL
      AND TRIM(source_id) <> ''
  ''');

  final outgoing = await db.query(
    'accounts',
    columns: ['id'],
    where: 'code=?',
    whereArgs: ['1030'],
    limit: 1,
  );

  if (outgoing.isEmpty) {
    await db.insert(
      'accounts',
      {
        'code': '1030',
        'name': 'شيكات صادرة / أوراق دفع',
        'type': 'LIABILITY',
        'normal_balance': 'CREDIT',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}

Future<int> accountId(DatabaseExecutor db, String code) async {
  final rows = await db.query(
    'accounts',
    columns: ['id'],
    where: 'code=?',
    whereArgs: [code],
    limit: 1,
  );
  if (rows.isEmpty) throw StateError('Missing account $code');
  return asInt(rows.first['id']);
}

Future<double> accountNet(DatabaseExecutor db, String code) async {
  final rows = await db.rawQuery(r'''
    SELECT COALESCE(SUM(l.debit-l.credit),0) AS n
    FROM gl_lines l
    JOIN accounts a ON a.id=l.account_id
    WHERE a.code=?
  ''', [code]);

  return asDouble(rows.first['n']);
}

Future<Map<String, Object?>> glTotals(DatabaseExecutor db) async {
  final row = (await db.rawQuery(r'''
    SELECT
      COUNT(*) AS c,
      COALESCE(SUM(debit),0) AS d,
      COALESCE(SUM(credit),0) AS cr
    FROM gl_lines
  ''')).first;

  return {
    'count': asInt(row['c']),
    'debit': asDouble(row['d']),
    'credit': asDouble(row['cr']),
  };
}

Future<int> unbalancedGl(DatabaseExecutor db) async {
  return firstInt(
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
}

Future<void> writeReport(Map<String, Object?> body) async {
  final home = Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return;

  final file = File(
    '$home${Platform.pathSeparator}Downloads'
    '${Platform.pathSeparator}Yalla_P0_008_RESULT.json',
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
    stderr.writeln('P0.008 ERROR: DB not found at $dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(dbPath);

  try {
    final version = firstInt(await db.rawQuery('PRAGMA user_version'));
    if (version != 55) {
      throw StateError(
        'P0.008 refused: expected DB user_version 55, found $version.',
      );
    }

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first.toString() != 'ok') {
      throw StateError('P0.008 refused: DB integrity_check is not OK.');
    }

    final chequeCount = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM cheques'),
    );
    final chequeVoucherCount = firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM vouchers WHERE LOWER(method)='cheque'",
      ),
    );
    final chequeReceiptCount = firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM payments WHERE LOWER(method)='cheque'",
      ),
    );
    final p0005Count = firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM gl_entries WHERE source='P0_AP_RECLASS'",
      ),
    );
    final p0008Count = firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM gl_entries WHERE source='P0_CHEQUE_FIX'",
      ),
    );
    final settlementCount = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM invoice_settlements'),
    );

    if (chequeCount != 0 ||
        chequeVoucherCount != 1 ||
        chequeReceiptCount != 0 ||
        p0005Count != 24 ||
        p0008Count != 0 ||
        settlementCount != 0 ||
        await unbalancedGl(db) != 0) {
      throw StateError(
        'P0.008 refused: live cheque/accounting baseline changed.',
      );
    }

    final voucher = await db.query(
      'vouchers',
      where: 'id=?',
      whereArgs: [voucherId],
      limit: 1,
    );

    if (voucher.length != 1) {
      throw StateError('P0.008 refused: audited cheque voucher not found.');
    }

    final v = voucher.first;
    if (v['voucher_number']?.toString() != voucherNumber ||
        v['voucher_type']?.toString() != 'PAYMENT' ||
        v['party_type']?.toString() != 'SUPPLIER' ||
        v['party_id']?.toString() != supplierId.toString() ||
        (asDouble(v['amount']) - amount).abs() > 0.01 ||
        v['method']?.toString().toLowerCase() != 'cheque' ||
        v['cheque_id'] != null ||
        asInt(v['gl_entry_id']) != originalVoucherGlId ||
        asInt(v['is_posted']) != 1) {
      throw StateError(
        'P0.008 refused: audited voucher fields changed: $v',
      );
    }

    final gl71 = await db.rawQuery(r'''
      SELECT
        COUNT(*) AS line_count,
        COALESCE(SUM(l.debit),0) AS d,
        COALESCE(SUM(l.credit),0) AS c,
        COALESCE(SUM(
          CASE WHEN a.code='1020' THEN l.debit-l.credit ELSE 0 END
        ),0) AS chq_effect
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      JOIN accounts a ON a.id=l.account_id
      WHERE e.id=? AND e.source='VOUCHER' AND e.source_id=?
    ''', [originalVoucherGlId, voucherId]);

    if (gl71.length != 1 ||
        asInt(gl71.first['line_count']) != 2 ||
        (asDouble(gl71.first['d']) - amount).abs() > 0.01 ||
        (asDouble(gl71.first['c']) - amount).abs() > 0.01 ||
        (asDouble(gl71.first['chq_effect']) + amount).abs() > 0.01) {
      throw StateError('P0.008 refused: original voucher GL changed: $gl71');
    }

    final p0005 = await db.rawQuery(r'''
      SELECT
        e.id,
        COUNT(l.id) AS line_count,
        COALESCE(SUM(
          CASE WHEN a.code='2200.S0002'
               THEN l.debit-l.credit ELSE 0 END
        ),0) AS canonical_ap_effect
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      JOIN accounts a ON a.id=l.account_id
      WHERE e.id=?
        AND e.source='P0_AP_RECLASS'
        AND e.source_id=?
      GROUP BY e.id
    ''', [originalApReclassGlId, originalVoucherGlId.toString()]);

    if (p0005.length != 1 ||
        asInt(p0005.first['line_count']) != 2 ||
        (asDouble(p0005.first['canonical_ap_effect']) - amount).abs() > 0.01) {
      throw StateError(
        'P0.008 refused: P0.005 supplier reclassification changed.',
      );
    }

    final account1020Before = await accountNet(db, '1020');
    if ((account1020Before + amount).abs() > 0.01) {
      throw StateError(
        'P0.008 refused: account 1020 expected -2000.00, '
        'found $account1020Before.',
      );
    }

    final apBefore = await accountNet(db, '2200.S0002');
    final totalsBefore = await glTotals(db);

    stdout.writeln(
      'P0.008 preflight PASS: exact historical cheque voucher identified.',
    );
    stdout.writeln(
      'P0.008 historical accounting before repair: '
      'Dr canonical supplier AP 2,000 / Cr legacy account 1020 2,000.',
    );
    stdout.writeln(
      'P0.008 policy: outgoing pending cheque belongs in liability 1030, '
      'not incoming-cheque asset 1020.',
    );

    if (!apply) return;

    late int chequeId;
    late int correctionGlId;

    await db.transaction((txn) async {
      await ensureSchema(txn);

      final outgoingAccountId = await accountId(txn, '1030');
      final incomingAccountId = await accountId(txn, '1020');

      final now = DateTime.now().toIso8601String();
      final voucherDate = v['date']?.toString() ?? now;
      final legacyUuid = 'legacy-voucher-$voucherId';

      chequeId = await txn.insert(
        'cheques',
        {
          'uuid': legacyUuid,
          'cheque_no': '',
          'cheque_type': 'outgoing',
          'status': 'pending',
          'drawer_name': '',
          'bank_name': '',
          'bank_branch': '',
          'amount': amount,
          'currency': v['currency']?.toString() ?? 'ILS',
          'issue_date': voucherDate,
          'due_date': voucherDate,
          'source_type': 'VOUCHER',
          'source_id': voucherId,
          'supplier_pid': supplierId.toString(),
          'client_id': null,
          'recipient_type': 'SUPPLIER',
          'recipient_id': supplierId.toString(),
          'recipient_name': 'ابو طارق الجعبري',
          'linked_payment_ids': '[]',
          'linked_repair_ids': '[]',
          'gl_entry_id': originalVoucherGlId,
          'notes': 'P0.008 recovered historical cheque from voucher P-0009. '
              'Original cheque number, bank, drawer and due date were not '
              'stored; complete them before lifecycle actions.',
          'origin_cheque_id': null,
          'is_endorsed': 0,
          'endorsed_at': null,
          'last_endorser_name': null,
          'auto_return_date': null,
          'return_reason': null,
          'is_legacy_incomplete': 1,
          'created_at': now,
          'updated_at': now,

          // Compatibility aliases.
          'supplier_id': supplierId,
          'payment_id': null,
          'date': voucherDate,
          'bank': '',
          'number': '',
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await txn.update(
        'vouchers',
        {
          'cheque_id': chequeId.toString(),
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [voucherId],
      );

      await txn.insert(
        'cheque_events',
        {
          'cheque_id': chequeId,
          'event_type': 'legacy_recovered',
          'from_status': null,
          'to_status': 'pending',
          'event_date': voucherDate,
          'gl_entry_id': originalVoucherGlId,
          'note': 'Recovered from historical voucher P-0009',
          'created_at': now,
        },
      );

      correctionGlId = await txn.insert(
        'gl_entries',
        {
          'date': voucherDate,
          'ref': voucherId,
          'source': 'P0_CHEQUE_FIX',
          'source_id': originalVoucherGlId.toString(),
          'note': 'P0.008 reclassifies historical outgoing cheque from '
              'incoming-cheque asset 1020 to outgoing-cheque liability 1030. '
              'Original VOUCHER GL #71 remains immutable.',
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await txn.insert(
        'gl_lines',
        {
          'entry_id': correctionGlId,
          'account_id': incomingAccountId,
          'debit': amount,
          'credit': 0.0,
          'party_type': null,
          'party_id': null,
          'invoice_id': null,
          'repair_id': null,
          'cheque_id': chequeId,
          'created_at': now,
        },
      );

      await txn.insert(
        'gl_lines',
        {
          'entry_id': correctionGlId,
          'account_id': outgoingAccountId,
          'debit': 0.0,
          'credit': amount,
          'party_type': null,
          'party_id': null,
          'invoice_id': null,
          'repair_id': null,
          'cheque_id': chequeId,
          'created_at': now,
        },
      );

      await txn.insert(
        'cheque_events',
        {
          'cheque_id': chequeId,
          'event_type': 'legacy_account_reclassified',
          'from_status': 'pending',
          'to_status': 'pending',
          'event_date': now,
          'gl_entry_id': correctionGlId,
          'note': 'Dr 1020 / Cr 1030 — 2,000.00 ILS',
          'created_at': now,
        },
      );
    });

    await db.execute('PRAGMA user_version = 56');

    final versionAfter = firstInt(await db.rawQuery('PRAGMA user_version'));
    final chequesAfter = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM cheques'),
    );
    final eventsAfter = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM cheque_events'),
    );
    final p0008After = firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM gl_entries WHERE source='P0_CHEQUE_FIX'",
      ),
    );
    final missingLinks = firstInt(
      await db.rawQuery(r'''
        SELECT COUNT(*)
        FROM vouchers v
        WHERE LOWER(v.method)='cheque'
          AND (
            COALESCE(v.cheque_id,'')=''
            OR NOT EXISTS (
              SELECT 1
              FROM cheques c
              WHERE CAST(c.id AS TEXT)=CAST(v.cheque_id AS TEXT)
                AND c.source_type='VOUCHER'
                AND c.source_id=v.id
            )
          )
      '''),
    );

    final account1020After = await accountNet(db, '1020');
    final account1030After = await accountNet(db, '1030');
    final apAfter = await accountNet(db, '2200.S0002');
    final totalsAfter = await glTotals(db);
    final unbalancedAfter = await unbalancedGl(db);
    final integrityAfter = await db.rawQuery('PRAGMA integrity_check');

    final glCountDelta =
        asInt(totalsAfter['count']) - asInt(totalsBefore['count']);
    final debitDelta =
        asDouble(totalsAfter['debit']) - asDouble(totalsBefore['debit']);
    final creditDelta =
        asDouble(totalsAfter['credit']) - asDouble(totalsBefore['credit']);

    if (versionAfter != 56 ||
        chequesAfter != 1 ||
        eventsAfter < 2 ||
        p0008After != 1 ||
        missingLinks != 0 ||
        account1020After.abs() > 0.01 ||
        (account1030After + amount).abs() > 0.01 ||
        (apAfter - apBefore).abs() > 0.01 ||
        glCountDelta != 2 ||
        (debitDelta - amount).abs() > 0.01 ||
        (creditDelta - amount).abs() > 0.01 ||
        unbalancedAfter != 0 ||
        integrityAfter.isEmpty ||
        integrityAfter.first.values.first.toString() != 'ok') {
      throw StateError(
        'P0.008 post-validation failed: '
        'version=$versionAfter cheques=$chequesAfter events=$eventsAfter '
        'fix=$p0008After missingLinks=$missingLinks '
        '1020=$account1020After 1030=$account1030After '
        'apBefore=$apBefore apAfter=$apAfter '
        'glLineDelta=$glCountDelta debitDelta=$debitDelta '
        'creditDelta=$creditDelta unbalanced=$unbalancedAfter',
      );
    }

    await writeReport({
      'status': 'PASS',
      'db_version': 56,
      'historical_voucher_id': voucherId,
      'historical_voucher_number': voucherNumber,
      'historical_cheque_id': chequeId,
      'historical_cheque_amount_ils': amount,
      'legacy_metadata_incomplete': true,
      'p0_cheque_fix_gl_id': correctionGlId,
      'account_1020_net_after': account1020After,
      'account_1030_net_after': account1030After,
      'supplier_ap_changed': false,
      'historical_original_gl_71_changed': false,
      'cheque_method_documents_missing_links': 0,
      'unbalanced_gl_entries': 0,
      'integrity_check': 'ok',
    });

    stdout.writeln(
      'P0.008 DATA REPAIR PASS: historical 2,000.00 ILS cheque recovered.',
    );
    stdout.writeln(
      'P0.008 historical GL preserved; immutable reclassification added.',
    );
    stdout.writeln(
      'P0.008 account 1020 net after repair: 0.00 ILS.',
    );
    stdout.writeln(
      'P0.008 outgoing cheque liability 1030: 2,000.00 ILS credit.',
    );
    stdout.writeln(
      'P0.008 supplier AP financial effect unchanged: PASS.',
    );
    stdout.writeln(
      'P0.008 cheque-method document linkage: 1/1 valid.',
    );
    stdout.writeln('P0.008 DB version migration: 55 -> 56 PASS.');
    stdout.writeln('P0.008 GL balance validation PASS.');
    stdout.writeln('P0.008 DB integrity PASS.');
  } finally {
    await db.close();
  }
}
