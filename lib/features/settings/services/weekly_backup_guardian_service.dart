import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/p16_security_tables.dart';

class BackupGuardianStatus {
  const BackupGuardianStatus({
    required this.weeklyEnabled,
    this.backupEmail,
    this.lastLocalBackupAt,
    this.lastExternalHandoffAt,
    this.nextDueAt,
    this.snoozedUntil,
  });

  final bool weeklyEnabled;
  final String? backupEmail;
  final DateTime? lastLocalBackupAt;
  final DateTime? lastExternalHandoffAt;
  final DateTime? nextDueAt;
  final DateTime? snoozedUntil;

  bool isDue(DateTime now) {
    if (!weeklyEnabled) return false;
    if (snoozedUntil != null && snoozedUntil!.isAfter(now)) return false;
    final due = nextDueAt;
    return due == null || !due.isAfter(now);
  }
}

class WeeklyBackupGuardianService {
  WeeklyBackupGuardianService._();

  static Future<BackupGuardianStatus> load() async {
    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final rows = await db.query(
      'backup_guardian_settings',
      where: 'id = 1',
      limit: 1,
    );
    final row = rows.first;
    DateTime? date(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return BackupGuardianStatus(
      weeklyEnabled: (row['weekly_enabled'] as num?)?.toInt() != 0,
      backupEmail: row['backup_email']?.toString(),
      lastLocalBackupAt: date(row['last_local_backup_at']),
      lastExternalHandoffAt: date(row['last_external_handoff_at']),
      nextDueAt: date(row['next_due_at']),
      snoozedUntil: date(row['snoozed_until']),
    );
  }

  static Future<void> savePreferences({
    required bool weeklyEnabled,
    String? backupEmail,
  }) async {
    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final now = DateTime.now().toUtc();
    final current = await load();
    await db.update(
      'backup_guardian_settings',
      {
        'weekly_enabled': weeklyEnabled ? 1 : 0,
        'backup_email': _nullIfBlank(backupEmail),
        if (weeklyEnabled && current.nextDueAt == null)
          'next_due_at': now.add(const Duration(days: 7)).toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = 1',
    );
  }

  static Future<void> recordLocalBackup(DateTime at) async {
    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final utc = at.toUtc();
    await db.update(
      'backup_guardian_settings',
      {
        'last_local_backup_at': utc.toIso8601String(),
        // A weekly cycle is complete only after an external handoff. If the
        // user declines the mail/cloud share now, remind again tomorrow.
        'snoozed_until': utc.add(const Duration(days: 1)).toIso8601String(),
        'updated_at': utc.toIso8601String(),
      },
      where: 'id = 1',
    );
  }

  static Future<void> snoozeOneDay() async {
    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final now = DateTime.now().toUtc();
    await db.update(
      'backup_guardian_settings',
      {
        'snoozed_until': now.add(const Duration(days: 1)).toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = 1',
    );
  }

  static Future<void> skipThisWeek() async {
    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final now = DateTime.now().toUtc();
    await db.update(
      'backup_guardian_settings',
      {
        'last_skipped_at': now.toIso8601String(),
        'next_due_at': now.add(const Duration(days: 7)).toIso8601String(),
        'snoozed_until': null,
        'updated_at': now.toIso8601String(),
      },
      where: 'id = 1',
    );
  }

  static String? _nullIfBlank(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}
