import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';

class InsuranceRenewalCandidate {
  const InsuranceRenewalCandidate({
    required this.id,
    required this.policyId,
    required this.renewalDate,
    required this.status,
    required this.daysRemaining,
    this.previousPolicyId,
    this.newPolicyId,
    this.lastContactAt,
    this.nextContactAt,
    this.outcome,
  });

  final String id;
  final String policyId;
  final String? previousPolicyId;
  final String? newPolicyId;
  final DateTime renewalDate;
  final String status;
  final int daysRemaining;
  final DateTime? lastContactAt;
  final DateTime? nextContactAt;
  final String? outcome;

  bool get isExpired => daysRemaining < 0 && status != 'RENEWED';
}

class InsuranceRenewalService {
  InsuranceRenewalService._();

  static const followUpStatuses = <String>{
    'PENDING',
    'NOT_CONTACTED',
    'CONTACTED',
    'NO_ANSWER',
    'WHATSAPP_SENT',
    'QUOTE_SENT',
    'ACCEPTED',
    'REJECTED',
    'RENEWED',
    'RENEWED_COMPETITOR',
    'CANCELLED',
  };

  static String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _date(Object? value) {
    final text = _clean(value);
    return text == null ? null : DateTime.tryParse(text);
  }

  static int _days(DateTime renewalDate, DateTime asOf) {
    final due = DateTime(renewalDate.year, renewalDate.month, renewalDate.day);
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    return due.difference(today).inDays;
  }

  static Future<List<InsuranceRenewalCandidate>> listCandidates({
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final reference = asOf ?? DateTime.now();
    final rows = await db.query(
      'insurance_renewals',
      orderBy: 'renewal_date ASC, id ASC',
    );
    return rows.map((row) {
      final renewalDate = DateTime.parse(row['renewal_date'].toString());
      return InsuranceRenewalCandidate(
        id: row['id'].toString(),
        policyId: row['policy_id'].toString(),
        previousPolicyId: _clean(row['previous_policy_id']),
        newPolicyId: _clean(row['new_policy_id']),
        renewalDate: renewalDate,
        status: row['status'].toString().trim().toUpperCase(),
        daysRemaining: _days(renewalDate, reference),
        lastContactAt: _date(row['last_contact_at']),
        nextContactAt: _date(row['next_contact_at']),
        outcome: _clean(row['outcome']),
      );
    }).toList(growable: false);
  }

  static Future<void> updateFollowUp({
    required String policyId,
    required String status,
    DateTime? lastContactAt,
    DateTime? nextContactAt,
    String? outcome,
    DatabaseExecutor? database,
  }) async {
    final canonicalStatus = status.trim().toUpperCase();
    if (!followUpStatuses.contains(canonicalStatus)) {
      throw ArgumentError('Unsupported insurance renewal follow-up status.');
    }
    final db = database ?? await DBService.database;
    await SyncFoundationService.writeOn<void>(db, (txn) async {
      final current = await txn.query(
        'insurance_renewals',
        columns: const ['status', 'new_policy_id'],
        where: 'policy_id=?',
        whereArgs: [policyId.trim()],
        limit: 1,
      );
      if (current.isEmpty) {
        throw StateError('Insurance renewal candidate not found.');
      }
      if (_clean(current.single['new_policy_id']) != null &&
          canonicalStatus != 'RENEWED') {
        throw StateError('A linked renewal cannot return to follow-up state.');
      }
      final changed = await txn.update(
        'insurance_renewals',
        {
          'status': canonicalStatus,
          'last_contact_at': lastContactAt?.toIso8601String(),
          'next_contact_at': nextContactAt?.toIso8601String(),
          'outcome': _clean(outcome),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'policy_id=?',
        whereArgs: [policyId.trim()],
      );
      if (changed != 1) {
        throw StateError('Insurance renewal follow-up update failed.');
      }
    });
  }
}
