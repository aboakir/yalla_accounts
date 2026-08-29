import 'package:sqflite/sqflite.dart';

class LicenseValidationState {
  const LicenseValidationState({
    required this.validationRequiredAt,
    required this.validationGraceUntil,
    this.lastAttemptAt,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastFailureReason,
    this.consecutiveFailures = 0,
  });

  final DateTime validationRequiredAt;
  final DateTime validationGraceUntil;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastFailureReason;
  final int consecutiveFailures;

  bool isDue(DateTime now) => !validationRequiredAt.isAfter(now.toUtc());
  bool isGraceExpired(DateTime now) =>
      !validationGraceUntil.isAfter(now.toUtc());
}

/// SEC.012 - local projection of the signed periodic-validation window.
///
/// The row is not authoritative. The actual deadline comes from the verified
/// signed license envelope (or the SEC.012 legacy transition defaults derived
/// from its signed issued_at timestamp). DB triggers use this projection as a
/// durable enforcement surface while the application remains open/offline.
class LicenseValidationTables {
  static const table = 'license_validation_state';

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        organization_id TEXT,
        license_id TEXT,
        validation_required_at TEXT NOT NULL,
        validation_grace_until TEXT NOT NULL,
        last_attempt_at TEXT,
        last_success_at TEXT,
        last_failure_at TEXT,
        last_failure_reason TEXT,
        consecutive_failures INTEGER NOT NULL DEFAULT 0,
        server_time_at_success TEXT,
        updated_at TEXT NOT NULL,
        CHECK(consecutive_failures >= 0),
        CHECK(datetime(validation_grace_until) >= datetime(validation_required_at))
      );
    ''');
  }

  static Future<void> projectSignedWindow(
    DatabaseExecutor db, {
    required String organizationId,
    required String licenseId,
    required DateTime validationRequiredAt,
    required DateTime validationGraceUntil,
    DateTime? serverTime,
    bool markSuccess = false,
  }) async {
    await ensure(db);
    final requiredAt = validationRequiredAt.toUtc();
    final graceUntil = validationGraceUntil.toUtc();
    if (graceUntil.isBefore(requiredAt)) {
      throw StateError(
          'SEC.012 validation grace cannot precede validation due.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(table, where: 'singleton_id = 1', limit: 1);
    final values = <String, Object?>{
      'organization_id': organizationId,
      'license_id': licenseId,
      'validation_required_at': requiredAt.toIso8601String(),
      'validation_grace_until': graceUntil.toIso8601String(),
      'updated_at': now,
    };
    if (markSuccess) {
      final successAt =
          (serverTime ?? DateTime.now()).toUtc().toIso8601String();
      values.addAll(<String, Object?>{
        'last_attempt_at': successAt,
        'last_success_at': successAt,
        'last_failure_at': null,
        'last_failure_reason': null,
        'consecutive_failures': 0,
        'server_time_at_success': successAt,
      });
    }

    if (rows.isEmpty) {
      await db.insert(table, <String, Object?>{
        'singleton_id': 1,
        ...values,
      });
    } else {
      await db.update(
        table,
        values,
        where: 'singleton_id = 1',
      );
    }
  }

  static Future<void> recordFailure(
    DatabaseExecutor db, {
    required String reason,
    DateTime? attemptedAt,
  }) async {
    await ensure(db);
    final rows = await db.query(table, where: 'singleton_id = 1', limit: 1);
    if (rows.isEmpty) return;
    final row = rows.single;
    final previous = (row['consecutive_failures'] as num?)?.toInt() ?? 0;
    final at = (attemptedAt ?? DateTime.now()).toUtc().toIso8601String();
    await db.update(
      table,
      <String, Object?>{
        'last_attempt_at': at,
        'last_failure_at': at,
        'last_failure_reason': reason,
        'consecutive_failures': previous + 1,
        'updated_at': at,
      },
      where: 'singleton_id = 1',
    );
  }

  static Future<LicenseValidationState?> current(DatabaseExecutor db) async {
    await ensure(db);
    final rows = await db.query(table, where: 'singleton_id = 1', limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final requiredAt =
        DateTime.tryParse(row['validation_required_at']?.toString() ?? '');
    final graceUntil =
        DateTime.tryParse(row['validation_grace_until']?.toString() ?? '');
    if (requiredAt == null || graceUntil == null) return null;

    DateTime? parse(String key) {
      final raw = row[key]?.toString();
      return raw == null || raw.isEmpty
          ? null
          : DateTime.tryParse(raw)?.toUtc();
    }

    return LicenseValidationState(
      validationRequiredAt: requiredAt.toUtc(),
      validationGraceUntil: graceUntil.toUtc(),
      lastAttemptAt: parse('last_attempt_at'),
      lastSuccessAt: parse('last_success_at'),
      lastFailureAt: parse('last_failure_at'),
      lastFailureReason: row['last_failure_reason']?.toString(),
      consecutiveFailures: (row['consecutive_failures'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final rows = await db.query(table, limit: 2);
    if (rows.length > 1) {
      throw StateError('SEC.012 allows at most one validation state row.');
    }
    if (rows.isEmpty) return;
    final state = await current(db);
    if (state == null ||
        state.validationGraceUntil.isBefore(state.validationRequiredAt)) {
      throw StateError('SEC.012 validation state is malformed.');
    }
  }
}
