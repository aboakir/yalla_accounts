import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/posting_engine.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

class RepairReconciliationIssue {
  const RepairReconciliationIssue({
    required this.repairId,
    required this.clientId,
    required this.fileValue,
    required this.ledgerGross,
    required this.paid,
    required this.arBalance,
    required this.difference,
    required this.repairable,
    required this.evidence,
    this.invoiceId,
    this.reason,
  });

  final String repairId;
  final int clientId;
  final String? invoiceId;
  final double fileValue;
  final double ledgerGross;
  final double paid;
  final double arBalance;
  final double difference;
  final bool repairable;
  final List<String> evidence;
  final String? reason;

  Map<String, Object?> toJson() => {
        'repair_id': repairId,
        'client_id': clientId,
        'invoice_id': invoiceId,
        'file_value': fileValue,
        'ledger_gross': ledgerGross,
        'paid': paid,
        'ar_balance': arBalance,
        'difference': difference,
        'repairable': repairable,
        'evidence': evidence,
        if (reason != null) 'reason': reason,
      };
}

class RepairReconciliationResult {
  const RepairReconciliationResult({
    required this.inspected,
    required this.repaired,
    required this.remaining,
    required this.correctedAmount,
    required this.logId,
    required this.issuesBefore,
    required this.issuesAfter,
  });

  final int inspected;
  final int repaired;
  final int remaining;
  final double correctedAmount;
  final int logId;
  final List<RepairReconciliationIssue> issuesBefore;
  final List<RepairReconciliationIssue> issuesAfter;
}

class RepairHistoricalReconciliationService {
  RepairHistoricalReconciliationService._();

  static const source = 'REPAIR_RECONCILIATION';
  static const actor = 'MIGRATION:HUMAN-007-008';

  static double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int? _i(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));

  static Future<List<RepairReconciliationIssue>> audit(
    DatabaseExecutor db,
  ) async {
    final historyTable = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='repair_edit_history'",
    );
    final latestEditSql = historyTable.isEmpty
        ? 'NULL'
        : '''(SELECT h.new_value FROM repair_edit_history h
          WHERE h.repair_id=r.id
          ORDER BY datetime(h.created_at) DESC, rowid DESC
          LIMIT 1)''';

    final repairs = await db.rawQuery('''
      SELECT
        r.id,
        r.client_id,
        r.invoice_id,
        r.fileValue,
        r.finalApprovedAmount,
        r.incomeAmount,
        r.status,
        r.isArchived,
        (SELECT i.id FROM invoices i
          WHERE i.repair_id=r.id
          ORDER BY datetime(i.created_at) DESC, rowid DESC
          LIMIT 1) AS linked_invoice_id,
        (SELECT i.total FROM invoices i
          WHERE i.repair_id=r.id
          ORDER BY datetime(i.created_at) DESC, rowid DESC
          LIMIT 1) AS linked_invoice_total,
        $latestEditSql AS latest_edit_value
      FROM repairs r
      ORDER BY datetime(r.receivedDate) ASC, r.rowid ASC
    ''');

    final issues = <RepairReconciliationIssue>[];
    for (final row in repairs) {
      final repairId = row['id']?.toString() ?? '';
      final clientId = _i(row['client_id']);
      if (repairId.isEmpty || clientId == null || clientId <= 0) continue;

      final truth = await RepairFinancialTruthService.load(
        repairId,
        executor: db,
      );
      if (truth.ledgerMismatch.abs() <= 0.01) continue;

      final evidence = <String>[];
      final finalApproved = row['finalApprovedAmount'];
      if (finalApproved != null &&
          (_d(finalApproved) - truth.fileValue).abs() <= 0.01) {
        evidence.add('FINAL_APPROVED_AMOUNT');
      }
      final latestEdit = row['latest_edit_value'];
      if (latestEdit != null &&
          (_d(latestEdit) - truth.fileValue).abs() <= 0.01) {
        evidence.add('REPAIR_EDIT_HISTORY');
      }
      final invoiceTotal = row['linked_invoice_total'];
      if (invoiceTotal != null &&
          (_d(invoiceTotal) - truth.fileValue).abs() <= 0.01) {
        evidence.add('LINKED_INVOICE');
      }

      final explicitInvoice = row['invoice_id']?.toString().trim();
      final linkedInvoice = row['linked_invoice_id']?.toString().trim();
      final invoiceId = explicitInvoice != null && explicitInvoice.isNotEmpty
          ? explicitInvoice
          : linkedInvoice;
      final hasFinancialDocument =
          invoiceId != null && invoiceId.trim().isNotEmpty;
      final hasFinancialGl = truth.ledgerGrossTotal.abs() > 0.01 ||
          truth.paid.abs() > 0.01 ||
          truth.customerArBalance.abs() > 0.01;
      final repairable =
          evidence.isNotEmpty && (hasFinancialDocument || hasFinancialGl);

      issues.add(
        RepairReconciliationIssue(
          repairId: repairId,
          clientId: clientId,
          invoiceId: invoiceId,
          fileValue: truth.fileValue,
          ledgerGross: truth.ledgerGrossTotal,
          paid: truth.paid,
          arBalance: truth.customerArBalance,
          difference: _round2(truth.fileValue - truth.ledgerGrossTotal),
          repairable: repairable,
          evidence: List.unmodifiable(evidence),
          reason: repairable
              ? null
              : !hasFinancialDocument && !hasFinancialGl
                  ? 'NO_FINANCIAL_DOCUMENT'
                  : 'INSUFFICIENT_CURRENT_VALUE_EVIDENCE',
        ),
      );
    }
    return List.unmodifiable(issues);
  }

  static Future<int> _accountId(
    DatabaseExecutor db,
    String code,
  ) async {
    final rows = await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Required reconciliation account missing: $code');
    }
    return _i(rows.first['id'])!;
  }

  static Future<int> _clientArAccountId(
    DatabaseExecutor db,
    int clientId,
  ) async {
    final clients = await db.query(
      'clients',
      columns: const ['account_id'],
      where: 'id=?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (clients.isNotEmpty) {
      final id = _i(clients.first['account_id']);
      if (id != null && id > 0) return id;
    }

    final canonical = await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: ['1200.C$clientId'],
      limit: 1,
    );
    if (canonical.isNotEmpty) return _i(canonical.first['id'])!;

    throw StateError(
      'Client $clientId has no canonical AR account for reconciliation.',
    );
  }

  static Future<RepairReconciliationResult> reconcile(
    Database db, {
    required String backupPath,
  }) async {
    final before = await audit(db);
    final repairable = before.where((issue) => issue.repairable).toList();
    var repaired = 0;
    var correctedAmount = 0.0;
    var logId = 0;

    await db.transaction((tx) async {
      final revenueAccount = await _accountId(tx, '4000');
      final changes = <Map<String, Object?>>[];

      for (final issue in repairable) {
        final current = await RepairFinancialTruthService.load(
          issue.repairId,
          executor: tx,
        );
        final correction =
            _round2(current.fileValue - current.ledgerGrossTotal);
        if (correction.abs() <= 0.01) continue;

        final existing = await tx.query(
          'gl_entries',
          columns: const ['id'],
          where: 'source=? AND source_id=?',
          whereArgs: [source, issue.repairId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          throw StateError(
            'Reconciliation posting already exists but mismatch remains for ${issue.repairId}.',
          );
        }

        final arAccount = await _clientArAccountId(tx, issue.clientId);
        final amount = correction.abs();
        final arLine = <String, Object?>{
          'account_id': arAccount,
          'debit': correction > 0 ? amount : 0.0,
          'credit': correction < 0 ? amount : 0.0,
          'party_type': 'CLIENT',
          'party_id': issue.clientId.toString(),
          'invoice_id': issue.invoiceId,
          'repair_id': issue.repairId,
        };
        final revenueLine = <String, Object?>{
          'account_id': revenueAccount,
          'debit': correction < 0 ? amount : 0.0,
          'credit': correction > 0 ? amount : 0.0,
          'invoice_id': issue.invoiceId,
          'repair_id': issue.repairId,
        };

        final glId = await PostingEngine.postEntryOn(
          ex: tx,
          date: DateTime.now().toUtc(),
          ref: 'REPAIR-RECON-${issue.repairId}',
          source: source,
          sourceId: issue.repairId,
          createdBy: actor,
          note: 'Historical repair reconciliation: ${current.ledgerGrossTotal.toStringAsFixed(2)} -> ${current.fileValue.toStringAsFixed(2)}',
          lines: [arLine, revenueLine],
        );

        await RepairFinancialTruthService.refreshRepairPaymentCache(
          tx,
          issue.repairId,
        );
        final afterTruth = await RepairFinancialTruthService.load(
          issue.repairId,
          executor: tx,
        );
        if (!afterTruth.isLedgerConsistent) {
          throw StateError(
            'Reconciliation failed to close ${issue.repairId}: ${afterTruth.ledgerMismatch}',
          );
        }

        await AuditTrailService.log(
          executor: tx,
          actorUserId: actor,
          actorRole: 'SYSTEM_MIGRATION',
          action: 'REPAIR_FINANCIAL_RECONCILED',
          entityType: 'repair',
          entityId: issue.repairId,
          before: issue.toJson(),
          after: {
            'file_value': afterTruth.fileValue,
            'paid': afterTruth.paid,
            'ar_balance': afterTruth.customerArBalance,
            'ledger_gross': afterTruth.ledgerGrossTotal,
            'mismatch': afterTruth.ledgerMismatch,
          },
          reason: 'HUMAN-007/HUMAN-008 historical reconciliation',
          metadata: {
            'gl_entry_id': glId,
            'evidence': issue.evidence,
            'backup_path': backupPath,
          },
        );

        repaired++;
        correctedAmount = _round2(correctedAmount + amount);
        changes.add({
          'repair_id': issue.repairId,
          'gl_entry_id': glId,
          'difference': correction,
          'evidence': issue.evidence,
        });
      }

      final afterInTx = await audit(tx);
      final unresolvedRepairable =
          afterInTx.where((issue) => issue.repairable).toList();
      if (unresolvedRepairable.isNotEmpty) {
        throw StateError(
          'Repair reconciliation left ${unresolvedRepairable.length} repairable mismatch(es).',
        );
      }

      logId = await tx.insert(
        'data_health_repair_log',
        {
          'run_at': DateTime.now().toUtc().toIso8601String(),
          'backup_path': backupPath,
          'changes_json': jsonEncode({
            'action': source,
            'repaired': repaired,
            'corrected_amount': correctedAmount,
            'changes': changes,
          }),
          'before_summary': jsonEncode({
            'mismatches': before.length,
            'repairable': repairable.length,
          }),
          'after_summary': jsonEncode({
            'mismatches': afterInTx.length,
            'repairable': afterInTx.where((issue) => issue.repairable).length,
          }),
        },
      );
    });

    final after = await audit(db);
    return RepairReconciliationResult(
      inspected: before.length,
      repaired: repaired,
      remaining: after.length,
      correctedAmount: correctedAmount,
      logId: logId,
      issuesBefore: before,
      issuesAfter: after,
    );
  }
}
