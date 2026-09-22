import 'package:sqflite/sqflite.dart';

/// Prevents legacy policy screens from mutating a policy that has entered the
/// canonical financial lifecycle.
class PolicyLegacyMutationGuard {
  PolicyLegacyMutationGuard._();

  static const blockedMessage =
      'هذه البوليصة مُرحّلة مالياً. استخدم مسار الملحق أو الإلغاء المعتمد بدلاً من التعديل أو الحذف المباشر.';

  static bool hasCanonicalPostingEvidence(Map<String, dynamic> row) {
    if (_hasValue(row['operation_id']) || _hasValue(row['gl_entry_id'])) {
      return true;
    }

    final status =
        (row['posting_status'] ?? '').toString().trim().toUpperCase();
    return status.isNotEmpty && status != 'DRAFT';
  }

  /// Reads the current row instead of trusting a potentially stale UI map.
  static Future<Map<String, dynamic>?> loadCurrent(
    DatabaseExecutor db,
    Map<String, dynamic> row, {
    dynamic fallbackId,
  }) async {
    final candidates = <({String column, dynamic value})>[];
    for (final column in const ['id', 'policy_id', 'uuid']) {
      final value = row[column];
      if (_hasValue(value)) candidates.add((column: column, value: value));
    }
    if (_hasValue(fallbackId)) {
      for (final column in const ['id', 'policy_id', 'uuid']) {
        if (!candidates.any(
          (candidate) =>
              candidate.column == column && candidate.value == fallbackId,
        )) {
          candidates.add((column: column, value: fallbackId));
        }
      }
    }

    for (final candidate in candidates) {
      try {
        final rows = await db.query(
          'insurance_policies',
          where: '${candidate.column}=?',
          whereArgs: [candidate.value],
          limit: 1,
        );
        if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.single);
      } on DatabaseException catch (error) {
        // Older isolated schemas may not contain every historical identifier.
        if (!error.toString().toLowerCase().contains('no such column')) rethrow;
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>> requireUnposted(
    DatabaseExecutor db,
    Map<String, dynamic> row, {
    dynamic fallbackId,
  }) async {
    final current = await loadCurrent(db, row, fallbackId: fallbackId);
    if (current == null) {
      throw StateError('Insurance policy no longer exists.');
    }
    if (hasCanonicalPostingEvidence(current)) {
      throw const PolicyLegacyMutationBlocked();
    }
    return current;
  }

  static ({String column, dynamic value})? locator(
    Map<String, dynamic> row,
  ) {
    for (final column in const ['id', 'policy_id', 'uuid']) {
      final value = row[column];
      if (_hasValue(value)) return (column: column, value: value);
    }
    return null;
  }

  static bool _hasValue(dynamic value) {
    if (value == null) return false;
    return value.toString().trim().isNotEmpty;
  }
}

class PolicyLegacyMutationBlocked implements Exception {
  const PolicyLegacyMutationBlocked();

  @override
  String toString() => PolicyLegacyMutationGuard.blockedMessage;
}
