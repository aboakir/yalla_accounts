import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/cheque_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';

class ChequeReconciliationIssue {
  const ChequeReconciliationIssue({
    required this.code,
    required this.recordId,
    required this.message,
    required this.severity,
    required this.repairable,
    this.data = const <String, Object?>{},
  });

  final String code;
  final String recordId;
  final String message;
  final String severity;
  final bool repairable;
  final Map<String, Object?> data;
}

class ChequeReconciliationReport {
  const ChequeReconciliationReport({
    required this.inspectedCheques,
    required this.inspectedChequeMethodVouchers,
    required this.inspectedChequeMethodReceipts,
    required this.policyScheduleCheques,
    required this.issues,
  });

  final int inspectedCheques;
  final int inspectedChequeMethodVouchers;
  final int inspectedChequeMethodReceipts;
  final int policyScheduleCheques;
  final List<ChequeReconciliationIssue> issues;

  int get repairableCount => issues.where((i) => i.repairable).length;
  int get errorCount => issues.where((i) => i.severity == 'ERROR').length;
  int get warningCount => issues.where((i) => i.severity == 'WARNING').length;
  int get financialMismatchCount => issues
      .where((i) =>
          i.severity == 'ERROR' &&
          i.code != 'LEGACY_CHEQUE_METADATA_INCOMPLETE')
      .length;
}

class ChequeReconciliationResult {
  const ChequeReconciliationResult({
    required this.before,
    required this.after,
    required this.repairedRecords,
    required this.createdChequeIds,
  });

  final ChequeReconciliationReport before;
  final ChequeReconciliationReport after;
  final int repairedRecords;
  final List<int> createdChequeIds;
}

class ChequeReconciliationService {
  ChequeReconciliationService._();

  static bool _isChequeMethod(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    return value == 'cheque' ||
        value == 'check' ||
        value == 'شيك' ||
        value == 'شيكات' ||
        value.contains('cheque') ||
        value.contains('check') ||
        value.contains('شيك');
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<int> _count(DatabaseExecutor db, String table) async {
    if (!await _tableExists(db, table)) return 0;
    final rows = await db.rawQuery('SELECT COUNT(*) n FROM $table');
    return (rows.single['n'] as num?)?.toInt() ?? 0;
  }

  static Future<void> _addRows(
    List<ChequeReconciliationIssue> issues, {
    required String code,
    required String message,
    required List<Map<String, Object?>> rows,
    required String idField,
    String severity = 'ERROR',
    bool repairable = false,
  }) async {
    for (final row in rows) {
      issues.add(ChequeReconciliationIssue(
        code: code,
        recordId: row[idField]?.toString() ?? '',
        message: message,
        severity: severity,
        repairable: repairable,
        data: row,
      ));
    }
  }

  static Future<ChequeReconciliationReport> audit(
    DatabaseExecutor db,
  ) async {
    await ChequeTables.ensureChequesSchema(db);
    final issues = <ChequeReconciliationIssue>[];
    final cheques = await db.query('cheques', orderBy: 'id');
    final vouchers = await db.query('vouchers', orderBy: 'date, id');
    final payments = await db.query('payments', orderBy: 'date, id');
    final chequeVouchers =
        vouchers.where((row) => _isChequeMethod(row['method'])).toList();
    final chequePayments =
        payments.where((row) => _isChequeMethod(row['method'])).toList();

    for (final voucher in chequeVouchers) {
      final id = voucher['id'].toString();
      final linked = await db.rawQuery(
        '''
        SELECT DISTINCT c.id
        FROM cheques c
        WHERE CAST(c.id AS TEXT)=COALESCE(?, '')
           OR c.payment_voucher_id=?
           OR (UPPER(COALESCE(c.source_type,''))='VOUCHER' AND c.source_id=?)
        ''',
        [voucher['cheque_id']?.toString(), id, id],
      );
      if (linked.isEmpty) {
        final evidence = await _legacyVoucherEvidence(db, voucher);
        issues.add(ChequeReconciliationIssue(
          code: 'VOUCHER_CHEQUE_WITHOUT_INSTRUMENT',
          recordId: id,
          message: 'Cheque-method voucher has no canonical instrument.',
          severity: 'ERROR',
          repairable: evidence != null,
          data: {
            'voucher_number': voucher['voucher_number'],
            'amount': voucher['amount'],
            'party_type': voucher['party_type'],
            'party_id': voucher['party_id'],
            'gl_entry_id': voucher['gl_entry_id'],
            'evidence_complete': evidence != null,
          },
        ));
      } else if (linked.length > 1) {
        issues.add(ChequeReconciliationIssue(
          code: 'VOUCHER_POINTS_TO_MULTIPLE_CHEQUES',
          recordId: id,
          message: 'Voucher resolves to multiple cheque records.',
          severity: 'ERROR',
          repairable: false,
          data: {'cheque_ids': linked.map((e) => e['id']).toList()},
        ));
      }

      final glEntryId = _asInt(voucher['gl_entry_id']);
      if (glEntryId != null && glEntryId > 0) {
        final gl = await db.query('gl_entries',
            where: 'id=? AND source=? AND source_id=?',
            whereArgs: [glEntryId, 'VOUCHER', id],
            limit: 1);
        if (gl.isNotEmpty &&
            ((voucher['is_posted'] as num?)?.toInt() ?? 0) == 0) {
          issues.add(ChequeReconciliationIssue(
            code: 'CHEQUE_VOUCHER_POSTING_METADATA_STALE',
            recordId: id,
            message:
                'Voucher has valid GL but legacy posting metadata is stale; posted document remains immutable.',
            severity: 'INFO',
            repairable: false,
            data: {
              'gl_entry_id': glEntryId,
              'status': voucher['status'],
              'is_posted': voucher['is_posted'],
            },
          ));
        }
      }
    }

    for (final payment in chequePayments) {
      final id = payment['id'].toString();
      final chequeId = _asInt(payment['cheque_id']);
      if (chequeId == null) {
        issues.add(ChequeReconciliationIssue(
          code: 'RECEIPT_CHEQUE_WITHOUT_INSTRUMENT',
          recordId: id,
          message: 'Cheque receipt row has no canonical cheque id.',
          severity: 'ERROR',
          repairable: false,
          data: {
            'receipt_number': payment['receipt_number'],
            'amount': payment['amount']
          },
        ));
      } else {
        final target = await db.query(
          'cheques',
          columns: const ['id'],
          where: 'id=?',
          whereArgs: [chequeId],
          limit: 1,
        );
        if (target.isEmpty) {
          issues.add(ChequeReconciliationIssue(
            code: 'RECEIPT_ORPHAN_CHEQUE_REFERENCE',
            recordId: id,
            message: 'Receipt/payment points to a missing cheque.',
            severity: 'ERROR',
            repairable: false,
            data: {'cheque_id': chequeId},
          ));
        }
      }
    }

    await _addRows(
      issues,
      code: 'ACCOUNTED_CHEQUE_WITHOUT_VOUCHER_LINK',
      message: 'Accounted cheque has no canonical voucher link.',
      idField: 'id',
      rows: await db.rawQuery(r'''
        SELECT c.id,c.source_type,c.source_id,c.gl_entry_id
        FROM cheques c        LEFT JOIN cheque_voucher_links vl ON vl.cheque_id=c.id
        WHERE vl.id IS NULL
          AND (c.gl_entry_id IS NOT NULL
            OR TRIM(COALESCE(c.source_type,''))<>''
            OR c.receipt_voucher_id IS NOT NULL
            OR TRIM(COALESCE(c.payment_voucher_id,''))<>'')
      '''),
    );

    await _addRows(
      issues,
      code: 'CHEQUE_LINKED_TO_MULTIPLE_VOUCHERS',
      message: 'Cheque is linked to more than one voucher.',
      idField: 'cheque_id',
      rows: await db.rawQuery(r'''
        SELECT cheque_id,COUNT(*) link_count
        FROM cheque_voucher_links
        GROUP BY cheque_id
        HAVING COUNT(*)>1
      '''),
    );

    await _addRows(
      issues,
      code: 'CHEQUE_VOUCHER_AMOUNT_MISMATCH',
      message: 'Cheque amount differs from voucher instrument amount.',
      idField: 'id',
      rows: await db.rawQuery(r'''
        SELECT c.id,c.amount cheque_amount,vl.amount link_amount
        FROM cheques c
        JOIN cheque_voucher_links vl ON vl.cheque_id=c.id        WHERE ABS(COALESCE(c.amount,0)-COALESCE(vl.amount,0))>0.005
      '''),
    );

    await _addRows(
      issues,
      code: 'CHEQUE_ALLOCATION_EXCEEDS_AMOUNT',
      message: 'Cheque allocations exceed cheque amount.',
      idField: 'id',
      rows: await db.rawQuery(r'''
        SELECT c.id,c.amount cheque_amount,COALESCE(SUM(a.amount),0) allocation_total
        FROM cheques c
        JOIN cheque_allocations a ON a.cheque_id=c.id
        GROUP BY c.id,c.amount
        HAVING COALESCE(SUM(a.amount),0)>c.amount+0.005
      '''),
    );

    await _addRows(
      issues,
      code: 'DUPLICATE_CHEQUE_ALLOCATION',
      message: 'Cheque has duplicate allocation rows.',
      idField: 'cheque_id',
      rows: await db.rawQuery(r'''
        SELECT cheque_id,allocation_type,COALESCE(target_id,'') target_id,COUNT(*) duplicate_count
        FROM cheque_allocations
        GROUP BY cheque_id,allocation_type,COALESCE(target_id,'')
        HAVING COUNT(*)>1
      '''),
    );
    await _addRows(
      issues,
      code: 'RECEIVED_CHEQUE_WITHOUT_DRAWER',
      message: 'Received cheque has no drawer.',
      idField: 'id',
      rows: await db.rawQuery(r'''
        SELECT id FROM cheques
        WHERE direction='RECEIVED'
          AND COALESCE(is_legacy_incomplete,0)=0
          AND TRIM(COALESCE(drawer_name,''))=''
      '''),
    );

    await _addRows(
      issues,
      code: 'ISSUED_CHEQUE_WITHOUT_PAYEE',
      message: 'Issued cheque has no payee.',
      idField: 'id',
      rows: await db.rawQuery(r'''
        SELECT id FROM cheques
        WHERE direction='ISSUED'
          AND COALESCE(is_legacy_incomplete,0)=0
          AND TRIM(COALESCE(recipient_name,''))=''
      '''),
    );

    await _addRows(
      issues,
      code: 'ISSUED_CHEQUE_WITHOUT_BOOK',
      message: 'Issued cheque has no cheque book.',
      idField: 'id',
      rows: await db.rawQuery(r'''
        SELECT id FROM cheques
        WHERE direction='ISSUED'
          AND COALESCE(is_legacy_incomplete,0)=0          AND TRIM(COALESCE(cheque_book_id,''))=''
      '''),
    );

    await _addRows(
      issues,
      code: 'CHEQUE_WITHOUT_PARTY',
      message: 'Cheque has no traceable party.',
      idField: 'id',
      rows: await db.rawQuery(r'''
        SELECT id,direction FROM cheques
        WHERE (direction='RECEIVED'
          AND client_id IS NULL
          AND TRIM(COALESCE(source_party_id,''))='')
        OR (direction='ISSUED'
          AND TRIM(COALESCE(recipient_id,''))=''
          AND TRIM(COALESCE(supplier_pid,''))=''
          AND TRIM(COALESCE(source_party_id,''))='')
      '''),
    );

    await _addRows(
      issues,
      code: 'DUPLICATE_ISSUED_CHEQUE_NUMBER',
      message: 'Cheque book contains a reused cheque number.',
      idField: 'cheque_book_id',
      rows: await db.rawQuery(r'''
        SELECT cheque_book_id,cheque_no,COUNT(*) duplicate_count
        FROM cheques
        WHERE direction='ISSUED'
          AND TRIM(COALESCE(cheque_book_id,''))<>''
          AND TRIM(COALESCE(cheque_no,''))<>''
        GROUP BY cheque_book_id,cheque_no
        HAVING COUNT(*)>1      '''),
    );

    await _addRows(
      issues,
      code: 'DEPOSITED_CHEQUE_WITHOUT_BATCH',
      message: 'Deposited cheque has no deposit batch.',
      idField: 'id',
      rows: await db.rawQuery(r'''
        SELECT c.id FROM cheques c
        LEFT JOIN cheque_deposit_items di ON di.cheque_id=c.id
        WHERE c.status='deposited' AND di.id IS NULL
      '''),
    );

    await _addRows(
      issues,
      code: 'ORPHAN_LEDGER_CHEQUE_REFERENCE',
      message: 'GL line references a missing cheque.',
      idField: 'line_id',
      rows: await db.rawQuery(r'''
        SELECT l.id line_id,l.entry_id,l.cheque_id
        FROM gl_lines l
        LEFT JOIN cheques c ON c.id=l.cheque_id
        WHERE l.cheque_id IS NOT NULL AND c.id IS NULL
      '''),
    );

    for (final row in cheques) {
      final id = _asInt(row['id'])!;
      final status = (row['status'] ?? '').toString().toLowerCase();
      final legacy = ((row['is_legacy_incomplete'] as num?)?.toInt() ?? 0) == 1;
      if (legacy) {
        issues.add(ChequeReconciliationIssue(
          code: 'LEGACY_CHEQUE_METADATA_INCOMPLETE',
          recordId: '$id',
          message: 'Recovered legacy cheque still needs physical metadata.',
          severity: 'WARNING',
          repairable: false,
        ));
      }

      if (const {'collected', 'cleared', 'returned', 'cancelled'}
          .contains(status)) {
        final event = await db.query(
          'cheque_events',
          columns: const ['id'],
          where: 'cheque_id=? AND event_type=?',
          whereArgs: [id, 'status:$status'],
          limit: 1,
        );
        if (event.isEmpty) {
          issues.add(ChequeReconciliationIssue(
            code: 'CHEQUE_STATUS_WITHOUT_EVENT',
            recordId: '$id',
            message: 'Terminal cheque status has no lifecycle event.',
            severity: 'ERROR',
            repairable: false,
            data: {'status': status},
          ));
        }
      }
      final requireGl = status == 'cleared' ||
          (status == 'collected' &&
              ((row['is_endorsed'] as num?)?.toInt() ?? 0) != 1) ||
          ((status == 'returned' || status == 'cancelled') &&
              row['gl_entry_id'] != null);
      if (requireGl) {
        final gl = await db.query(
          'gl_entries',
          columns: const ['id'],
          where: 'source=? AND source_id=?',
          whereArgs: ['CHEQUE_STATUS', '$id:$status'],
          limit: 1,
        );
        if (gl.isEmpty) {
          issues.add(ChequeReconciliationIssue(
            code: 'CHEQUE_STATUS_WITHOUT_GL',
            recordId: '$id',
            message: 'Lifecycle status has no accounting transaction.',
            severity: 'ERROR',
            repairable: false,
            data: {'status': status},
          ));
        }
      }
    }

    final policySchedules = await _count(db, 'insurance_policy_cheques');
    if (policySchedules > 0) {
      issues.add(ChequeReconciliationIssue(
        code: 'INSURANCE_POLICY_CHEQUE_SCHEDULES',
        recordId: 'insurance_policy_cheques',
        message:
            'Insurance policy cheque rows are non-GL payment-plan source records.',
        severity: 'INFO',
        repairable: false,
        data: {'count': policySchedules},
      ));
    }

    return ChequeReconciliationReport(
      inspectedCheques: cheques.length,
      inspectedChequeMethodVouchers: chequeVouchers.length,
      inspectedChequeMethodReceipts: chequePayments.length,
      policyScheduleCheques: policySchedules,
      issues: issues,
    );
  }

  static Future<Map<String, Object?>?> _legacyVoucherEvidence(
    DatabaseExecutor db,
    Map<String, Object?> voucher,
  ) async {
    if ((voucher['voucher_type'] ?? '').toString().toUpperCase() != 'PAYMENT') {
      return null;
    }
    final amount = _asDouble(voucher['amount']);
    final partyType = (voucher['party_type'] ?? '').toString().toUpperCase();
    final partyId = (voucher['party_id'] ?? '').toString().trim();
    final glEntryId = _asInt(voucher['gl_entry_id']);
    if (amount <= 0 ||
        partyType != 'SUPPLIER' ||
        partyId.isEmpty ||
        glEntryId == null) {
      return null;
    }
    final entry = await db.query(
      'gl_entries',
      where: 'id=? AND source=? AND source_id=?',
      whereArgs: [glEntryId, 'VOUCHER', voucher['id'].toString()],
      limit: 1,
    );
    if (entry.isEmpty) return null;

    final totals = await db.rawQuery(
      '''SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c
         FROM gl_lines WHERE entry_id=?''',
      [glEntryId],
    );
    final debit = _asDouble(totals.single['d']);
    final credit = _asDouble(totals.single['c']);
    if ((debit - credit).abs() > 0.005 || (debit - amount).abs() > 0.005) {
      return null;
    }

    final supplier = await db.query(
      'suppliers',
      columns: const ['id', 'name'],
      where: 'id=?',
      whereArgs: [int.tryParse(partyId) ?? -1],
      limit: 1,
    );
    if (supplier.isEmpty) return null;
    final chequeCredit = await db.rawQuery(
      '''SELECT l.account_id,a.code,a.name,l.credit
         FROM gl_lines l
         JOIN accounts a ON a.id=l.account_id
         WHERE l.entry_id=? AND l.credit>0
           AND a.code IN ('1020','1030')
         ORDER BY l.id''',
      [glEntryId],
    );
    if (chequeCredit.length != 1 ||
        (_asDouble(chequeCredit.single['credit']) - amount).abs() > 0.005) {
      return null;
    }

    return {
      'supplier_name': supplier.single['name'],
      'gl_entry_id': glEntryId,
      'cheque_account_id': chequeCredit.single['account_id'],
      'cheque_account_code': chequeCredit.single['code'],
      'gl_created_at': entry.single['created_at'],
    };
  }

  static Future<ChequeReconciliationResult> reconcileSafe(
    Database db, {
    required String backupPath,
  }) async {
    final before = await audit(db);
    final created = <int>[];
    var repaired = 0;
    await LicenseRuntimeTables.runTrustedMigrationBackfill(db, () async {
      final vouchers = await db.query('vouchers', orderBy: 'date, id');
      for (final voucher
          in vouchers.where((v) => _isChequeMethod(v['method']))) {
        final voucherId = voucher['id'].toString();
        final existing = await db.rawQuery(
          '''SELECT id FROM cheques
             WHERE payment_voucher_id=?
                OR (UPPER(COALESCE(source_type,''))='VOUCHER' AND source_id=?)
             LIMIT 1''',
          [voucherId, voucherId],
        );
        if (existing.isNotEmpty) continue;

        final evidence = await _legacyVoucherEvidence(db, voucher);
        if (evidence == null) continue;

        final chequeId = await SyncFoundationService.transaction<int>(
          db,
          (txn) async {
            final recheck = await txn.rawQuery(
              '''SELECT id FROM cheques
                 WHERE payment_voucher_id=?
                    OR (UPPER(COALESCE(source_type,''))='VOUCHER' AND source_id=?)
                 LIMIT 1''',
              [voucherId, voucherId],
            );
            if (recheck.isNotEmpty) return _asInt(recheck.single['id'])!;
            final amount = _asDouble(voucher['amount']);
            final partyId = voucher['party_id'].toString();
            final supplierName = evidence['supplier_name'].toString();
            final glEntryId = _asInt(evidence['gl_entry_id'])!;
            final now = DateTime.now().toUtc().toIso8601String();
            final stableKey = 'legacy-voucher:$voucherId';

            final newChequeId = await txn.insert(
              'cheques',
              {
                'uuid': stableKey,
                'instrument_key': stableKey,
                'cheque_no': '',
                'cheque_type': 'outgoing',
                'direction': 'ISSUED',
                'status': 'issued',
                'drawer_name': '',
                'bank_name': '',
                'bank_branch': '',
                'amount': amount,
                'currency': (voucher['currency'] ?? 'ILS').toString(),
                'issue_date': voucher['date']?.toString(),
                'due_date': null,
                'source_type': 'VOUCHER',
                'source_id': voucherId,
                'payment_voucher_id': voucherId,
                'source_party_type': 'SUPPLIER',
                'source_party_id': partyId,
                'supplier_pid': partyId,
                'supplier_id': int.tryParse(partyId),
                'recipient_type': 'SUPPLIER',
                'recipient_id': partyId,
                'recipient_name': supplierName,
                'linked_payment_ids': '[]',
                'linked_repair_ids': '[]',
                'gl_entry_id': glEntryId,
                'notes':
                    'Recovered from historical cheque voucher; physical metadata unknown.',
                'is_legacy_incomplete': 1,
                'created_by': 'MIGRATION:CHEQUE_RECONCILIATION',
                'created_at': voucher['created_at']?.toString() ??
                    voucher['date']?.toString() ??
                    now,
                'updated_at': now,
                'payment_id': null,
                'date': voucher['date']?.toString(),
                'bank': '',
                'number': '',
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            );

            await txn.insert(
              'cheque_voucher_links',
              {
                'cheque_id': newChequeId,
                'voucher_type': 'PAYMENT',
                'voucher_id': voucherId,
                'instrument_key': stableKey,
                'amount': amount,
                'created_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            );

            final reference = (voucher['reference'] ?? '').toString().trim();
            var allocationType = 'PARTY_ACCOUNT';
            var targetId = partyId;
            if (reference.isNotEmpty) {
              final invoice = await txn.query(
                'purchase_invoices',
                columns: const ['id'],
                where: 'id=?',
                whereArgs: [reference],
                limit: 1,
              );
              if (invoice.isNotEmpty) {
                allocationType = 'PURCHASE_INVOICE';
                targetId = reference;
              }
            }
            await txn.insert(
              'cheque_allocations',
              {
                'cheque_id': newChequeId,
                'voucher_type': 'PAYMENT',
                'voucher_id': voucherId,
                'allocation_type': allocationType,
                'target_id': targetId,
                'amount': amount,
                'created_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            );

            await txn.insert('cheque_events', {
              'cheque_id': newChequeId,
              'event_type': 'recovered_legacy_instrument',
              'from_status': null,
              'to_status': 'issued',
              'event_date': now,
              'gl_entry_id': glEntryId,
              'actor_user_id': 'MIGRATION:CHEQUE_RECONCILIATION',
              'reason':
                  'Recovered from historical voucher and balanced GL evidence',
              'metadata_json': jsonEncode({
                'backup_path': backupPath,
                'voucher_id': voucherId,
              }),
              'note':
                  'Physical cheque number, bank, book and maturity remain unknown.',
              'created_at': now,
            });
            await txn.insert('cheque_events', {
              'cheque_id': newChequeId,
              'event_type': 'initial_accounting',
              'from_status': 'issued',
              'to_status': 'issued',
              'event_date': now,
              'gl_entry_id': glEntryId,
              'actor_user_id': 'MIGRATION:CHEQUE_RECONCILIATION',
              'created_at': now,
            });

            int? reclassGlId;
            if (evidence['cheque_account_code']?.toString() == '1020') {
              final outgoing = await txn.query(
                'accounts',
                columns: const ['id'],
                where: 'code=?',
                whereArgs: const ['1030'],
                limit: 1,
              );
              if (outgoing.isEmpty) {
                throw StateError('Outgoing cheque account 1030 is missing.');
              }
              final oldAccountId = _asInt(evidence['cheque_account_id'])!;
              final outgoingId = _asInt(outgoing.single['id'])!;
              reclassGlId = await DBService.postEntryGLOn(
                ex: txn,
                date: DateTime.tryParse(voucher['date']?.toString() ?? '') ??
                    DateTime.now(),
                source: 'CHEQUE_RECONCILIATION',
                sourceId: '$stableKey:reclass',
                createdBy: 'MIGRATION:CHEQUE_RECONCILIATION',
                note:
                    'Legacy cheque account split: 1020 generic -> 1030 issued',
                lines: [
                  {
                    'account_id': oldAccountId,
                    'debit': amount,
                    'credit': 0.0,
                    'cheque_id': newChequeId,
                  },
                  {
                    'account_id': outgoingId,
                    'debit': 0.0,
                    'credit': amount,
                    'cheque_id': newChequeId,
                  },
                ],
              );
              await txn.insert('cheque_events', {
                'cheque_id': newChequeId,
                'event_type': 'legacy_account_reclassified',
                'from_status': 'issued',
                'to_status': 'issued',
                'event_date': now,
                'gl_entry_id': reclassGlId,
                'actor_user_id': 'MIGRATION:CHEQUE_RECONCILIATION',
                'note':
                    '1020 -> 1030 classification only; original GL preserved.',
                'created_at': now,
              });
            }

            await AuditTrailService.log(
              executor: txn,
              actorUserId: 'MIGRATION:CHEQUE_RECONCILIATION',
              actorRole: 'system',
              action: 'CHEQUE_LEGACY_INSTRUMENT_RECOVERED',
              entityType: 'cheque',
              entityId: newChequeId.toString(),
              before: voucher,
              after: {
                'cheque_id': newChequeId,
                'voucher_id': voucherId,
                'amount': amount,
                'direction': 'ISSUED',
                'status': 'issued',
                'is_legacy_incomplete': 1,
                'reclassification_gl_entry_id': reclassGlId,
              },
              reason:
                  'Historical cheque voucher had balanced GL evidence but no cheque row.',
              metadata: {
                'backup_path': backupPath,
                'original_gl_entry_id': glEntryId,
                'original_cheque_account_code': evidence['cheque_account_code'],
              },
            );

            return newChequeId;
          },
        );

        if (!created.contains(chequeId)) {
          created.add(chequeId);
          repaired++;
        }
      }
    });

    final after = await audit(db);
    return ChequeReconciliationResult(
      before: before,
      after: after,
      repairedRecords: repaired,
      createdChequeIds: created,
    );
  }
}
