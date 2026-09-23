import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

enum InsuranceAlertWindow { today, next7, next14, next30, overdue, all }

class InsuranceAlertItem {
  const InsuranceAlertItem({
    required this.key,
    required this.type,
    required this.dueAt,
    required this.severity,
    required this.message,
    required this.status,
    this.partyId,
    this.policyId,
    this.claimId,
    this.sourceId,
  });

  final String key;
  final String type;
  final DateTime dueAt;
  final String severity;
  final String message;
  final String status;
  final String? partyId;
  final String? policyId;
  final String? claimId;
  final String? sourceId;

  bool isOverdue(DateTime asOf) {
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    final due = DateTime(dueAt.year, dueAt.month, dueAt.day);
    return due.isBefore(today);
  }
}

class InsuranceAlertCenterService {
  InsuranceAlertCenterService._();

  static const supportedTypes = <String>{
    'POLICY_EXPIRY',
    'DRIVING_LICENSE_EXPIRY',
    'OUTSTANDING_INSTALLMENT',
    'CHEQUE_DUE',
    'RETURNED_CHEQUE',
    'CLAIM_FOLLOW_UP',
    'MISSING_DOCUMENTS',
    'PENDING_SETTLEMENT',
    'CUSTOMER_FOLLOW_UP',
    'QUOTE_RESPONSE',
  };

  static DateTime? _date(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : DateTime.tryParse(text);
  }

  static String? _clean(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _matchesWindow(
    DateTime dueAt,
    DateTime asOf,
    InsuranceAlertWindow window,
  ) {
    if (window == InsuranceAlertWindow.all) return true;
    final today = _dateOnly(asOf);
    final due = _dateOnly(dueAt);
    final days = due.difference(today).inDays;
    switch (window) {
      case InsuranceAlertWindow.today:
        return days == 0;
      case InsuranceAlertWindow.next7:
        return days >= 0 && days <= 7;
      case InsuranceAlertWindow.next14:
        return days >= 0 && days <= 14;
      case InsuranceAlertWindow.next30:
        return days >= 0 && days <= 30;
      case InsuranceAlertWindow.overdue:
        return days < 0;
      case InsuranceAlertWindow.all:
        return true;
    }
  }

  static String _severityFor(DateTime dueAt, DateTime asOf) {
    final days = _dateOnly(dueAt).difference(_dateOnly(asOf)).inDays;
    if (days <= 3) return 'HIGH';
    if (days <= 14) return 'MEDIUM';
    return 'NORMAL';
  }

  static Future<List<InsuranceAlertItem>> listAlerts({
    DateTime? asOf,
    InsuranceAlertWindow window = InsuranceAlertWindow.all,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final reference = asOf ?? DateTime.now();
    final byKey = <String, InsuranceAlertItem>{};

    void add(InsuranceAlertItem item) {
      if (!_matchesWindow(item.dueAt, reference, window)) return;
      byKey[item.key] = item;
    }

    final persisted = await db.query(
      'insurance_alerts',
      where:
          "UPPER(COALESCE(status,'OPEN')) NOT IN ('CLOSED','CANCELLED','RESOLVED')",
      orderBy: 'due_at ASC, id ASC',
    );
    for (final row in persisted) {
      final dueAt = _date(row['due_at']);
      if (dueAt == null) continue;
      final type =
          (row['alert_type'] ?? 'UNKNOWN').toString().trim().toUpperCase();
      add(InsuranceAlertItem(
        key: 'PERSISTED:${row['id']}',
        type: type,
        dueAt: dueAt,
        severity: (row['severity'] ?? _severityFor(dueAt, reference))
            .toString()
            .trim()
            .toUpperCase(),
        message: _clean(row['message']) ?? type,
        status: (row['status'] ?? 'OPEN').toString().trim().toUpperCase(),
        partyId: _clean(row['party_id']),
        policyId: _clean(row['policy_id']),
        claimId: _clean(row['claim_id']),
        sourceId: row['id']?.toString(),
      ));
    }

    await _appendPaymentSchedules(db, reference, add);
    await _appendChequeAlerts(db, reference, add);
    await _appendClaims(db, reference, add);
    await _appendSettlements(db, reference, add);
    await _appendProspectFollowUps(db, reference, add);
    await _appendQuoteResponses(db, reference, add);

    final result = byKey.values.toList(growable: false)
      ..sort((a, b) {
        final byDue = a.dueAt.compareTo(b.dueAt);
        if (byDue != 0) return byDue;
        final bySeverity = b.severity.compareTo(a.severity);
        return bySeverity != 0 ? bySeverity : a.type.compareTo(b.type);
      });
    return result;
  }

  static Future<void> _appendPaymentSchedules(
    DatabaseExecutor db,
    DateTime reference,
    void Function(InsuranceAlertItem) add,
  ) async {
    for (final spec in const [
      ('insurance_policy_installments', 'INSTALLMENT'),
      ('insurance_policy_promissories', 'PROMISSORY'),
    ]) {
      final rows = await db.rawQuery('''
        SELECT s.id,s.policy_id,s.amount,s.due_date,p.sell_price,
          COALESCE((
            SELECT SUM(pp.amount)
            FROM insurance_policy_payments pp
            WHERE pp.policy_id=s.policy_id
              AND pp.direction='CUSTOMER_RECEIPT'
              AND UPPER(COALESCE(pp.status,'POSTED'))='POSTED'
          ),0) AS collected
        FROM ${spec.$1} s
        JOIN insurance_policies p ON p.id=s.policy_id
        WHERE s.due_date IS NOT NULL AND TRIM(s.due_date)<>''
      ''');
      for (final row in rows) {
        final dueAt = _date(row['due_date']);
        if (dueAt == null) continue;
        final sale = (row['sell_price'] as num?)?.toDouble() ??
            double.tryParse('${row['sell_price']}') ??
            0;
        final collected = (row['collected'] as num?)?.toDouble() ??
            double.tryParse('${row['collected']}') ??
            0;
        if (sale > 0 && collected + 0.005 >= sale) continue;
        final id = row['id'].toString();
        final policyId = row['policy_id'].toString();
        final amount = (row['amount'] as num?)?.toDouble() ??
            double.tryParse('${row['amount']}') ??
            0;
        add(InsuranceAlertItem(
          key: 'SCHEDULE:${spec.$2}:$id',
          type: 'OUTSTANDING_INSTALLMENT',
          dueAt: dueAt,
          severity: _severityFor(dueAt, reference),
          message: spec.$2 == 'PROMISSORY'
              ? 'Promissory schedule due: ${amount.toStringAsFixed(2)}'
              : 'Installment due: ${amount.toStringAsFixed(2)}',
          status: 'OPEN',
          policyId: policyId,
          sourceId: id,
        ));
      }
    }
  }

  static Future<void> _appendChequeAlerts(
    DatabaseExecutor db,
    DateTime reference,
    void Function(InsuranceAlertItem) add,
  ) async {
    final rows = await db.rawQuery('''
      SELECT DISTINCT c.id,c.status,c.due_date,c.amount,c.cheque_no,pp.policy_id
      FROM cheques c
      JOIN insurance_policy_payments pp ON pp.cheque_id=c.id
      WHERE c.due_date IS NOT NULL AND TRIM(c.due_date)<>''
        AND pp.policy_id IS NOT NULL
        AND (
          UPPER(COALESCE(pp.status,'POSTED'))='POSTED'
          OR LOWER(COALESCE(c.status,''))='returned'
        )
    ''');
    for (final row in rows) {
      final dueAt = _date(row['due_date']);
      if (dueAt == null) continue;
      final status = (row['status'] ?? '').toString().trim().toLowerCase();
      final id = row['id'].toString();
      final policyId = _clean(row['policy_id']);
      if (status == 'returned') {
        add(InsuranceAlertItem(
          key: 'CHEQUE:RETURNED:$id',
          type: 'RETURNED_CHEQUE',
          dueAt: dueAt,
          severity: 'HIGH',
          message: 'Returned cheque ${_clean(row['cheque_no']) ?? id}',
          status: 'OPEN',
          policyId: policyId,
          sourceId: id,
        ));
        continue;
      }
      if ({'cleared', 'cancelled', 'canceled'}.contains(status)) continue;
      add(InsuranceAlertItem(
        key: 'CHEQUE:DUE:$id',
        type: 'CHEQUE_DUE',
        dueAt: dueAt,
        severity: _severityFor(dueAt, reference),
        message: 'Cheque due ${_clean(row['cheque_no']) ?? id}',
        status: 'OPEN',
        policyId: policyId,
        sourceId: id,
      ));
    }
  }

  static Future<void> _appendClaims(
    DatabaseExecutor db,
    DateTime reference,
    void Function(InsuranceAlertItem) add,
  ) async {
    final rows = await db.query(
      'insurance_claims',
      where: "UPPER(COALESCE(status,'NEW')) NOT IN ('CLOSED','REJECTED')",
    );
    for (final row in rows) {
      final status = (row['status'] ?? 'NEW').toString().trim().toUpperCase();
      final anchor = _date(row['updated_at']) ??
          _date(row['reported_at']) ??
          _date(row['created_at']) ??
          reference;
      final dueAt = _dateOnly(anchor).add(const Duration(days: 1));
      final id = row['id'].toString();
      final policyId = _clean(row['policy_id']);
      add(InsuranceAlertItem(
        key: 'CLAIM:FOLLOWUP:$id',
        type: 'CLAIM_FOLLOW_UP',
        dueAt: dueAt,
        severity: _severityFor(dueAt, reference),
        message: 'Claim follow-up ${_clean(row['claim_number']) ?? id}',
        status: 'OPEN',
        partyId: _clean(row['insured_party_id']),
        policyId: policyId,
        claimId: id,
        sourceId: id,
      ));
      if (status == 'DOCUMENTS_REQUIRED') {
        add(InsuranceAlertItem(
          key: 'CLAIM:DOCUMENTS:$id',
          type: 'MISSING_DOCUMENTS',
          dueAt: dueAt,
          severity: 'HIGH',
          message: 'Claim documents are required',
          status: 'OPEN',
          partyId: _clean(row['insured_party_id']),
          policyId: policyId,
          claimId: id,
          sourceId: id,
        ));
      }
    }
  }

  static Future<void> _appendSettlements(
    DatabaseExecutor db,
    DateTime reference,
    void Function(InsuranceAlertItem) add,
  ) async {
    final rows = await db.query(
      'insurance_settlements',
      where:
          "UPPER(COALESCE(status,'DRAFT')) NOT IN ('PAID','CLOSED','CANCELLED','POSTED')",
    );
    for (final row in rows) {
      final dueAt = _date(row['period_end']);
      if (dueAt == null) continue;
      final id = row['id'].toString();
      add(InsuranceAlertItem(
        key: 'SETTLEMENT:PENDING:$id',
        type: 'PENDING_SETTLEMENT',
        dueAt: dueAt,
        severity: _severityFor(dueAt, reference),
        message: 'Insurance company settlement is pending',
        status: 'OPEN',
        sourceId: id,
      ));
    }
  }

  static Future<void> _appendProspectFollowUps(
    DatabaseExecutor db,
    DateTime reference,
    void Function(InsuranceAlertItem) add,
  ) async {
    final rows = await db.query(
      'insurance_prospects',
      where:
          "next_contact_at IS NOT NULL AND TRIM(next_contact_at)<>'' AND UPPER(COALESCE(status,'')) NOT IN ('CLOSED','CONVERTED','LOST','REJECTED','CANCELLED')",
    );
    for (final row in rows) {
      final dueAt = _date(row['next_contact_at']);
      if (dueAt == null) continue;
      final id = row['id'].toString();
      add(InsuranceAlertItem(
        key: 'PROSPECT:FOLLOWUP:$id',
        type: 'CUSTOMER_FOLLOW_UP',
        dueAt: dueAt,
        severity: _severityFor(dueAt, reference),
        message: 'Customer follow-up is due',
        status: 'OPEN',
        partyId: _clean(row['party_id']),
        sourceId: id,
      ));
    }
  }

  static Future<void> _appendQuoteResponses(
    DatabaseExecutor db,
    DateTime reference,
    void Function(InsuranceAlertItem) add,
  ) async {
    final rows = await db.query(
      'insurance_quotes',
      where:
          "UPPER(COALESCE(status,'')) IN ('OFFERED','SENT','QUOTE_SENT','AWAITING_RESPONSE')",
    );
    for (final row in rows) {
      final requested = _date(row['requested_at']);
      if (requested == null) continue;
      final dueAt = _dateOnly(requested).add(const Duration(days: 2));
      final id = row['id'].toString();
      add(InsuranceAlertItem(
        key: 'QUOTE:RESPONSE:$id',
        type: 'QUOTE_RESPONSE',
        dueAt: dueAt,
        severity: _severityFor(dueAt, reference),
        message: 'Insurance quote is awaiting customer response',
        status: 'OPEN',
        partyId: _clean(row['party_id']),
        sourceId: id,
      ));
    }
  }
}
