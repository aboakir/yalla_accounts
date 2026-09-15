import 'package:sqflite/sqflite.dart';

class LicenseRuntimeMode {
  static const activationRequired = 'ACTIVATION_REQUIRED';
  static const writable = 'WRITABLE';
  static const readOnlyExpired = 'READ_ONLY_EXPIRED';
  static const readOnlySuspended = 'READ_ONLY_SUSPENDED';
  static const readOnlyRevoked = 'READ_ONLY_REVOKED';
  static const readOnlyValidationRequired = 'READ_ONLY_VALIDATION_REQUIRED';

  static const readOnlyModes = <String>{
    readOnlyExpired,
    readOnlySuspended,
    readOnlyRevoked,
    readOnlyValidationRequired,
  };
}

/// SEC.011 - local operational mode.
///
/// This table is a runtime projection only. It is never authoritative for
/// license dates, subscription status, entitlements, or signatures. Those facts
/// continue to come from the signed license envelope and server lifecycle
/// responses. DB triggers use this projection to make READ ONLY enforcement
/// comprehensive across old and new write surfaces.
class LicenseRuntimeTables {
  static const table = 'license_runtime_state';

  static const Set<String> _technicalExemptTables = <String>{
    // Version metadata must advance during atomic non-destructive upgrades.
    'schema_migrations',
    'cloud_identity_links',
    'sync_entity_registry',
    'sync_change_log',
    'sync_mutation_context',
    'sync_conflicts',
    'sync_remote_candidates',
    'sync_outbox_links',
    table,
    'organizations',
    'organization_identity',
    'installation_identity',
    'license_activation_state',
    'license_validation_state',
    'owner_bootstrap_state',
    'auth_roles',
    'auth_permissions',
    'auth_role_permissions',
    'auth_sessions',
    'app_audit_events',
    'backup_runs',
    'backup_guardian_settings',
    'password_reset_grants',
    'activation_codes',
    'domain_events',
    'outbox_messages',
    'data_health_repair_log',
    'sqlite_sequence',
  };

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        mode TEXT NOT NULL,
        reason TEXT,
        organization_id TEXT,
        subscription_id TEXT,
        license_id TEXT,
        effective_at TEXT NOT NULL,
        license_expires_at TEXT,
        source TEXT NOT NULL,
        last_verified_at TEXT,
        updated_at TEXT NOT NULL,
        CHECK(mode IN (
          'ACTIVATION_REQUIRED',
          'WRITABLE',
          'READ_ONLY_EXPIRED',
          'READ_ONLY_SUSPENDED',
          'READ_ONLY_REVOKED',
          'READ_ONLY_VALIDATION_REQUIRED'
        )),
        CHECK(source IN (
          'LOCAL_BOOTSTRAP',
          'SIGNED_LICENSE',
          'SERVER_LIFECYCLE'
        ))
      );
    ''');

    final existing = await db.query(table, where: 'singleton_id = 1', limit: 1);
    if (existing.isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert(table, <String, Object?>{
        'singleton_id': 1,
        'mode': LicenseRuntimeMode.activationRequired,
        'reason':
            'No verified runtime license decision has been projected yet.',
        'effective_at': now,
        'source': 'LOCAL_BOOTSTRAP',
        'updated_at': now,
      });
    }

    await installOperationalTriggers(db);
  }

  static Future<void> upgradeForSec012(Database db) async {
    await db.transaction((txn) async {
      final triggers = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' "
        "AND name LIKE 'yalla_sec011_ro_%'",
      );
      for (final row in triggers) {
        final name = row['name']?.toString() ?? '';
        if (_safeIdentifier(name)) {
          await txn.execute('DROP TRIGGER IF EXISTS $name');
        }
      }

      final tableRows = await txn.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        <Object?>[table],
      );
      final sql =
          tableRows.isEmpty ? '' : tableRows.first['sql']?.toString() ?? '';
      if (sql.isNotEmpty && !sql.contains('READ_ONLY_VALIDATION_REQUIRED')) {
        await txn.execute('ALTER TABLE $table RENAME TO ${table}_sec011_old');
        await txn.execute('''
          CREATE TABLE $table (
            singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
            mode TEXT NOT NULL,
            reason TEXT,
            organization_id TEXT,
            subscription_id TEXT,
            license_id TEXT,
            effective_at TEXT NOT NULL,
            license_expires_at TEXT,
            source TEXT NOT NULL,
            last_verified_at TEXT,
            updated_at TEXT NOT NULL,
            CHECK(mode IN (
              'ACTIVATION_REQUIRED',
              'WRITABLE',
              'READ_ONLY_EXPIRED',
              'READ_ONLY_SUSPENDED',
              'READ_ONLY_REVOKED',
              'READ_ONLY_VALIDATION_REQUIRED'
            )),
            CHECK(source IN (
              'LOCAL_BOOTSTRAP',
              'SIGNED_LICENSE',
              'SERVER_LIFECYCLE'
            ))
          );
        ''');
        await txn.execute('''
          INSERT INTO $table(
            singleton_id, mode, reason, organization_id, subscription_id,
            license_id, effective_at, license_expires_at, source,
            last_verified_at, updated_at
          )
          SELECT singleton_id, mode, reason, organization_id, subscription_id,
                 license_id, effective_at, license_expires_at, source,
                 last_verified_at, updated_at
          FROM ${table}_sec011_old;
        ''');
        await txn.execute('DROP TABLE ${table}_sec011_old');
      }
    });

    await ensure(db);
  }

  /// v71: backup metadata must stay writable when business data is read only.
  /// Audit append-only triggers are deliberately retained.
  static Future<void> upgradeBackupAvailability(DatabaseExecutor db) async {
    for (final name in [
      'app_audit_events',
      'backup_runs',
      'backup_guardian_settings'
    ]) {
      for (final operation in ['insert', 'update', 'delete']) {
        await db.execute(
            'DROP TRIGGER IF EXISTS yalla_sec011_ro_${name}_$operation');
      }
    }
  }

  static Future<void> installOperationalTriggers(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );

    for (final row in rows) {
      final name = row['name']?.toString() ?? '';
      if (name.isEmpty || _technicalExemptTables.contains(name)) continue;
      if (name == 'users') {
        await _installUserTriggers(db);
        continue;
      }
      if (!_safeIdentifier(name)) continue;

      for (final operation in const <String>['INSERT', 'UPDATE', 'DELETE']) {
        final triggerName =
            'yalla_sec011_ro_${name}_${operation.toLowerCase()}';
        await db.execute('DROP TRIGGER IF EXISTS $triggerName');
        await db.execute('''
          CREATE TRIGGER $triggerName
          BEFORE $operation ON $name
          WHEN
            EXISTS (
              SELECT 1 FROM $table
              WHERE singleton_id = 1
                AND mode IN (
                  'READ_ONLY_EXPIRED',
                  'READ_ONLY_SUSPENDED',
                  'READ_ONLY_REVOKED',
                  'READ_ONLY_VALIDATION_REQUIRED'
                )
            )
            OR EXISTS (
              SELECT 1 FROM $table
              WHERE singleton_id = 1
                AND datetime(effective_at) > datetime('now', '+2 minutes')
            )
            OR EXISTS (
              SELECT 1 FROM license_validation_state
              WHERE singleton_id = 1
                AND datetime(validation_grace_until) <= datetime('now')
            )
            OR EXISTS (
              SELECT 1 FROM license_activation_state
              WHERE singleton_id = 1
                AND status = 'ACTIVE'
                AND license_expires_at IS NOT NULL
                AND datetime(license_expires_at) <= datetime('now')
            )
          BEGIN
            SELECT RAISE(
              ABORT,
              'YALLA_READ_ONLY: subscription does not permit new operational writes'
            );
          END;
        ''');
      }
    }
  }

  static Future<void> _installUserTriggers(DatabaseExecutor db) async {
    const readOnlyCondition = '''
      EXISTS (
        SELECT 1 FROM license_runtime_state
        WHERE singleton_id = 1
          AND mode IN (
            'READ_ONLY_EXPIRED',
            'READ_ONLY_SUSPENDED',
            'READ_ONLY_REVOKED',
            'READ_ONLY_VALIDATION_REQUIRED'
          )
      )
      OR EXISTS (
        SELECT 1 FROM license_runtime_state
        WHERE singleton_id = 1
          AND datetime(effective_at) > datetime('now', '+2 minutes')
      )
      OR EXISTS (
        SELECT 1 FROM license_validation_state
        WHERE singleton_id = 1
          AND datetime(validation_grace_until) <= datetime('now')
      )
      OR EXISTS (
        SELECT 1 FROM license_activation_state
        WHERE singleton_id = 1
          AND status = 'ACTIVE'
          AND license_expires_at IS NOT NULL
          AND datetime(license_expires_at) <= datetime('now')
      )
    ''';

    for (final name in const [
      'yalla_sec011_ro_users_insert',
      'yalla_sec011_ro_users_delete',
      'yalla_sec011_ro_users_business_update',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $name');
    }

    await db.execute('''
      CREATE TRIGGER yalla_sec011_ro_users_insert
      BEFORE INSERT ON users
      WHEN $readOnlyCondition
      BEGIN
        SELECT RAISE(
          ABORT,
          'YALLA_READ_ONLY: new users are disabled while subscription is read only'
        );
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER yalla_sec011_ro_users_delete
      BEFORE DELETE ON users
      WHEN $readOnlyCondition
      BEGIN
        SELECT RAISE(
          ABORT,
          'YALLA_READ_ONLY: user deletion is disabled while subscription is read only'
        );
      END;
    ''');

    // Authentication/recovery metadata remains writable so existing users can
    // still sign in and recover access. Business identity, role, status and
    // workshop/subscription fields cannot be changed in READ ONLY.
    await db.execute('''
      CREATE TRIGGER yalla_sec011_ro_users_business_update
      BEFORE UPDATE ON users
      WHEN ($readOnlyCondition) AND (
        NEW.name IS NOT OLD.name OR
        NEW.email IS NOT OLD.email OR
        NEW.role IS NOT OLD.role OR
        NEW.status IS NOT OLD.status OR
        NEW.is_owner IS NOT OLD.is_owner OR
        NEW.organization_id IS NOT OLD.organization_id OR
        NEW.workshop_logo_path IS NOT OLD.workshop_logo_path OR
        NEW.workshop_address IS NOT OLD.workshop_address OR
        NEW.country IS NOT OLD.country OR
        NEW.province IS NOT OLD.province OR
        NEW.city IS NOT OLD.city OR
        NEW.street IS NOT OLD.street OR
        NEW.workshop_phone IS NOT OLD.workshop_phone OR
        NEW.phone_numbers IS NOT OLD.phone_numbers OR
        NEW.free_trial_start IS NOT OLD.free_trial_start OR
        NEW.free_trial_end IS NOT OLD.free_trial_end OR
        NEW.subscription_date IS NOT OLD.subscription_date OR
        NEW.subscription_end_date IS NOT OLD.subscription_end_date OR
        NEW.subscription_amount IS NOT OLD.subscription_amount OR
        NEW.payment_status IS NOT OLD.payment_status OR
        NEW.payment_method IS NOT OLD.payment_method OR
        NEW.payment_receipt_path IS NOT OLD.payment_receipt_path
      )
      BEGIN
        SELECT RAISE(
          ABORT,
          'YALLA_READ_ONLY: user/workshop mutation is disabled while subscription is read only'
        );
      END;
    ''');
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final rows = await db.query(table, limit: 2);
    if (rows.length != 1) {
      throw StateError('SEC.011 requires exactly one runtime license row.');
    }

    final mode = rows.single['mode']?.toString() ?? '';
    const allowed = <String>{
      LicenseRuntimeMode.activationRequired,
      LicenseRuntimeMode.writable,
      LicenseRuntimeMode.readOnlyExpired,
      LicenseRuntimeMode.readOnlySuspended,
      LicenseRuntimeMode.readOnlyRevoked,
      LicenseRuntimeMode.readOnlyValidationRequired,
    };
    if (!allowed.contains(mode)) {
      throw StateError('SEC.011 invalid runtime mode: $mode');
    }
  }

  static bool _safeIdentifier(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
}
