import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';

class InsurancePeriodReconciliation {
  const InsurancePeriodReconciliation({
    required this.periodStart,
    required this.periodEnd,
    required this.glDebit,
    required this.glCredit,
    required this.unbalancedGlEntries,
    required this.malformedPolicies,
    required this.malformedPayments,
    required this.negativeCustomerBalances,
    required this.negativeInsurerBalances,
    required this.pendingSettlements,
    required this.foreignKeyViolations,
    required this.issues,
  });
  final DateTime periodStart;
  final DateTime periodEnd;
  final double glDebit;
  final double glCredit;
  final int unbalancedGlEntries;
  final int malformedPolicies;
  final int malformedPayments;
  final int negativeCustomerBalances;
  final int negativeInsurerBalances;
  final int pendingSettlements;
  final int foreignKeyViolations;
  final List<String> issues;

  bool get isClean => issues.isEmpty;

  Map<String, Object?> toJson() => {
        'period_start': periodStart.toIso8601String(),
        'period_end': periodEnd.toIso8601String(),
        'gl_debit': glDebit,
        'gl_credit': glCredit,
        'unbalanced_gl_entries': unbalancedGlEntries,
        'malformed_policies': malformedPolicies,
        'malformed_payments': malformedPayments,
        'negative_customer_balances': negativeCustomerBalances,
        'negative_insurer_balances': negativeInsurerBalances,
        'pending_settlements': pendingSettlements,
        'foreign_key_violations': foreignKeyViolations,
        'issues': issues,
        'is_clean': isClean,
      };
}

class InsurancePeriodCloseRecord {
  const InsurancePeriodCloseRecord({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.closedAt,
    required this.closedBy,
    required this.status,
    required this.reconciliation,
  });

  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime closedAt;
  final String closedBy;
  final String status;
  final InsurancePeriodReconciliation reconciliation;
}

class InsurancePeriodCloseService {
  InsurancePeriodCloseService._();

  static DateTime _start(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _end(DateTime value) => DateTime(
        value.year,
        value.month,
        value.day,
        23,
        59,
        59,
        999,
      );

  static double _n(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _i(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _money(double value) => (value * 100).round() / 100;
  static Future<void> assertOpen(
    DatabaseExecutor db,
    DateTime date,
  ) async {
    final iso = date.toIso8601String();
    final rows = await db.rawQuery(
      "SELECT id FROM insurance_period_closes WHERE status='CLOSED' "
      'AND ? >= period_start AND ? <= period_end LIMIT 1',
      [iso, iso],
    );
    if (rows.isNotEmpty) {
      throw StateError('Insurance accounting period is closed.');
    }
  }

  static Future<InsurancePeriodReconciliation> reconcile({
    required DateTime periodStart,
    required DateTime periodEnd,
    DatabaseExecutor? executor,
  }) async {
    final start = _start(periodStart);
    final end = _end(periodEnd);
    if (end.isBefore(start)) {
      throw ArgumentError('Insurance close period is invalid.');
    }
    final db = executor ?? await DBService.database;
    final startIso = start.toIso8601String();
    final endIso = end.toIso8601String();
    final gl = (await db.rawQuery(
      '''SELECT COALESCE(SUM(l.debit),0) debit,
                COALESCE(SUM(l.credit),0) credit
         FROM gl_entries e
         JOIN gl_lines l ON l.entry_id=e.id
         WHERE e.date>=? AND e.date<=?''',
      [startIso, endIso],
    ))
        .single;
    final glDebit = _money(_n(gl['debit']));
    final glCredit = _money(_n(gl['credit']));

    final unbalanced = await db.rawQuery(
      '''SELECT e.id
         FROM gl_entries e
         JOIN gl_lines l ON l.entry_id=e.id
         WHERE e.date>=? AND e.date<=?
         GROUP BY e.id
         HAVING ABS(COALESCE(SUM(l.debit),0) -
                    COALESCE(SUM(l.credit),0)) > 0.005''',
      [startIso, endIso],
    );

    final malformedPolicyRow = (await db.rawQuery(
      '''SELECT COUNT(*) n
         FROM insurance_policies p
         LEFT JOIN gl_entries g ON g.id=p.gl_entry_id         WHERE p.posting_status='POSTED'
           AND p.reversed_at IS NULL
           AND (p.gl_entry_id IS NULL OR g.id IS NULL)''',
    ))
        .single;

    final malformedPaymentRow = (await db.rawQuery(
      '''SELECT COUNT(*) n
         FROM insurance_policy_payments pp
         LEFT JOIN payments p ON p.id=pp.payment_id
         LEFT JOIN receipt_headers rh
           ON rh.receipt_number=pp.receipt_number
         LEFT JOIN vouchers v ON v.id=pp.voucher_id
         WHERE UPPER(COALESCE(pp.status,'POSTED'))='POSTED'
           AND (
             (pp.direction='CUSTOMER_RECEIPT' AND
               (pp.receipt_number IS NULL OR pp.payment_id IS NULL
                OR p.id IS NULL OR rh.receipt_number IS NULL))
             OR
             (pp.direction IN ('INSURER_PAYMENT','REFUND') AND
               (pp.voucher_id IS NULL OR TRIM(pp.voucher_id)=''
                OR v.id IS NULL))
           )''',
    ))
        .single;
    final negativeCustomerRow = (await db.rawQuery(
      '''SELECT COUNT(*) n FROM (
           SELECT p.id,
             COALESCE(p.net_sale_amount,0)
             - COALESCE(SUM(CASE WHEN pp.status='POSTED'
                 AND pp.direction='CUSTOMER_RECEIPT'
                 THEN pp.amount ELSE 0 END),0)
             + COALESCE(SUM(CASE WHEN pp.status='POSTED'
                 AND pp.direction='REFUND'
                 THEN pp.amount ELSE 0 END),0) outstanding
           FROM insurance_policies p
           LEFT JOIN insurance_policy_payments pp ON pp.policy_id=p.id
           WHERE p.posting_status='POSTED' AND p.reversed_at IS NULL
           GROUP BY p.id
           HAVING outstanding < -0.005
         ) x''',
    ))
        .single;

    final negativeInsurerRow = (await db.rawQuery(
      '''SELECT COUNT(*) n FROM (
           SELECT p.id,
             COALESCE(p.net_insurer_payable,0)
             - COALESCE(SUM(CASE WHEN pp.status='POSTED'
                 AND pp.direction='INSURER_PAYMENT'                 THEN pp.amount ELSE 0 END),0) outstanding
           FROM insurance_policies p
           LEFT JOIN insurance_policy_payments pp ON pp.policy_id=p.id
           WHERE p.posting_status='POSTED' AND p.reversed_at IS NULL
           GROUP BY p.id
           HAVING outstanding < -0.005
         ) x''',
    ))
        .single;

    final pendingSettlementRow = (await db.rawQuery(
      '''SELECT COUNT(*) n
         FROM insurance_settlements
         WHERE UPPER(COALESCE(status,'DRAFT')) IN ('DRAFT','POSTED')
           AND period_start<=? AND period_end>=?''',
      [endIso, startIso],
    ))
        .single;

    final fkViolations = await db.rawQuery('PRAGMA foreign_key_check');

    final malformedPolicies = _i(malformedPolicyRow['n']);
    final malformedPayments = _i(malformedPaymentRow['n']);
    final negativeCustomerBalances = _i(negativeCustomerRow['n']);
    final negativeInsurerBalances = _i(negativeInsurerRow['n']);
    final pendingSettlements = _i(pendingSettlementRow['n']);
    final issues = <String>[];
    if ((glDebit - glCredit).abs() > 0.005) {
      issues.add('Period GL debit and credit totals do not balance.');
    }
    if (unbalanced.isNotEmpty) {
      issues.add(
        unbalanced.length.toString() +
            ' GL entries are individually unbalanced.',
      );
    }
    if (malformedPolicies > 0) {
      issues.add(
        malformedPolicies.toString() +
            ' posted policies are missing canonical GL.',
      );
    }
    if (malformedPayments > 0) {
      issues.add(
        malformedPayments.toString() +
            ' policy payments have broken receipt/voucher links.',
      );
    }
    if (negativeCustomerBalances > 0) {
      issues.add(
        negativeCustomerBalances.toString() +
            ' policies have negative customer balances.',
      );
    }
    if (negativeInsurerBalances > 0) {
      issues.add(
        negativeInsurerBalances.toString() +
            ' policies have negative insurer balances.',
      );
    }
    if (pendingSettlements > 0) {
      issues.add(
        pendingSettlements.toString() +
            ' insurance settlements are still open.',
      );
    }
    if (fkViolations.isNotEmpty) {
      issues.add(
        fkViolations.length.toString() + ' foreign-key violations exist.',
      );
    }

    return InsurancePeriodReconciliation(
      periodStart: start,
      periodEnd: end,
      glDebit: glDebit,
      glCredit: glCredit,
      unbalancedGlEntries: unbalanced.length,
      malformedPolicies: malformedPolicies,
      malformedPayments: malformedPayments,
      negativeCustomerBalances: negativeCustomerBalances,
      negativeInsurerBalances: negativeInsurerBalances,
      pendingSettlements: pendingSettlements,
      foreignKeyViolations: fkViolations.length,
      issues: List.unmodifiable(issues),
    );
  }

  static Future<InsurancePeriodCloseRecord> closePeriod({
    required DateTime periodStart,
    required DateTime periodEnd,
    String? closedBy,
    DatabaseExecutor? database,
  }) async {
    final permit = await AuthorizationGuard.require(PermissionKeys.periodClose);
    final start = _start(periodStart);
    final end = _end(periodEnd);
    if (end.isBefore(start)) {
      throw ArgumentError('Insurance close period is invalid.');
    }
    final db = database ?? await DBService.database;
    final actor = (closedBy ?? '').trim().isNotEmpty
        ? closedBy!.trim()
        : (permit?.id ?? 'SYSTEM');
    final id = 'INS-CLOSE:' +
        start.toIso8601String().substring(0, 10) +
        ':' +
        end.toIso8601String().substring(0, 10);
    return SyncFoundationService.writeOn<InsurancePeriodCloseRecord>(
      db,
      (txn) async {
        final exact = await txn.query(
          'insurance_period_closes',
          where: 'id=? AND status=?',
          whereArgs: [id, 'CLOSED'],
          limit: 1,
        );
        if (exact.isNotEmpty) {
          return _recordFromRow(exact.single);
        }

        final overlap = await txn.rawQuery(
          '''SELECT id FROM insurance_period_closes
             WHERE status='CLOSED'
               AND NOT (period_end < ? OR period_start > ?)
             LIMIT 1''',
          [start.toIso8601String(), end.toIso8601String()],
        );
        if (overlap.isNotEmpty) {
          throw StateError(
            'Insurance close period overlaps an existing close.',
          );
        }

        final reconciliation = await reconcile(
          periodStart: start,
          periodEnd: end,
          executor: txn,
        );
        if (!reconciliation.isClean) {
          throw StateError(
            'Insurance reconciliation failed: ' +
                reconciliation.issues.join(' | '),
          );
        }

        final closedAt = DateTime.now();
        await txn.insert('insurance_period_closes', {
          'id': id,
          'period_start': start.toIso8601String(),
          'period_end': end.toIso8601String(),
          'closed_at': closedAt.toIso8601String(),
          'closed_by': actor,
          'status': 'CLOSED',
          'reconciliation_json': jsonEncode(
            reconciliation.toJson(),
          ),
        });
        return InsurancePeriodCloseRecord(
          id: id,
          periodStart: start,
          periodEnd: end,
          closedAt: closedAt,
          closedBy: actor,
          status: 'CLOSED',
          reconciliation: reconciliation,
        );
      },
    );
  }

  static InsurancePeriodCloseRecord _recordFromRow(
    Map<String, Object?> row,
  ) {
    final payload = jsonDecode(
      (row['reconciliation_json'] ?? '{}').toString(),
    ) as Map<String, dynamic>;
    final issues = (payload['issues'] as List?)
            ?.map((entry) => entry.toString())
            .toList(growable: false) ??
        const <String>[];
    final reconciliation = InsurancePeriodReconciliation(
      periodStart: DateTime.parse(row['period_start'].toString()),
      periodEnd: DateTime.parse(row['period_end'].toString()),
      glDebit: _n(payload['gl_debit']),
      glCredit: _n(payload['gl_credit']),
      unbalancedGlEntries: _i(payload['unbalanced_gl_entries']),
      malformedPolicies: _i(payload['malformed_policies']),
      malformedPayments: _i(payload['malformed_payments']),
      negativeCustomerBalances: _i(payload['negative_customer_balances']),
      negativeInsurerBalances: _i(payload['negative_insurer_balances']),
      pendingSettlements: _i(payload['pending_settlements']),
      foreignKeyViolations: _i(payload['foreign_key_violations']),
      issues: issues,
    );
    return InsurancePeriodCloseRecord(
      id: row['id'].toString(),
      periodStart: DateTime.parse(row['period_start'].toString()),
      periodEnd: DateTime.parse(row['period_end'].toString()),
      closedAt: DateTime.parse(row['closed_at'].toString()),
      closedBy: (row['closed_by'] ?? '').toString(),
      status: row['status'].toString(),
      reconciliation: reconciliation,
    );
  }
}
