import 'package:sqflite/sqflite.dart';

import '../database_constants.dart';

/// SEC.001 — local organization identity foundation.
///
/// Phase 1 remains a single-organization desktop database. This schema gives
/// that organization a permanent UUID without moving accounting data to the
/// cloud or introducing licensing/subscription semantics ahead of SEC.002+.
class OrganizationIdentityTables {
  static Future<void> ensure(DatabaseExecutor db) async {
    await _createOrganizations(db);
    await _createOrganizationIdentity(db);
    await _ensureScopedColumns(db);

    final organizationId = await _ensureCurrentOrganization(db);
    await _backfillCurrentScope(db, organizationId);
    await _createScopeIndexes(db);
    await _createScopeGuards(db);
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final identity = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id = 1',
      limit: 2,
    );
    if (identity.length != 1) {
      throw StateError(
        'SEC.001 requires exactly one current organization identity.',
      );
    }

    final organizationId = identity.single['organization_id']?.toString() ?? '';
    if (!_looksLikeUuid(organizationId)) {
      throw StateError('SEC.001 current organization ID is not a UUID.');
    }

    final organization = await db.query(
      'organizations',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [organizationId],
      limit: 1,
    );
    if (organization.isEmpty) {
      throw StateError('SEC.001 current organization row is missing.');
    }

    for (final table in ['users', 'workshop_settings']) {
      final unscoped = Sqflite.firstIntValue(
            await db.rawQuery(
              "SELECT COUNT(*) FROM $table "
              "WHERE organization_id IS NULL "
              "OR TRIM(organization_id) = '' "
              "OR organization_id <> ?",
              [organizationId],
            ),
          ) ??
          0;
      if (unscoped != 0) {
        throw StateError(
          'SEC.001 found $unscoped rows outside the current organization in $table.',
        );
      }
    }
  }

  static Future<void> _createOrganizations(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS organizations (
        id TEXT PRIMARY KEY,
        display_name TEXT,
        country_code TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_organizations_status
      ON organizations(status);
    ''');
  }

  static Future<void> _createOrganizationIdentity(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS organization_identity (
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        organization_id TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        FOREIGN KEY(organization_id) REFERENCES organizations(id)
          ON DELETE RESTRICT
      );
    ''');
  }

  static Future<void> _ensureScopedColumns(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      table: 'users',
      column: 'organization_id',
      type: 'TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: 'workshop_settings',
      column: 'organization_id',
      type: 'TEXT',
    );
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db, {
    required String table,
    required String column,
    required String type,
  }) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name']?.toString() == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
    }
  }

  static Future<String> _ensureCurrentOrganization(DatabaseExecutor db) async {
    final identity = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );

    if (identity.isNotEmpty) {
      final organizationId =
          identity.first['organization_id']?.toString() ?? '';
      if (!_looksLikeUuid(organizationId)) {
        throw StateError(
          'SEC.001 organization identity is invalid: $organizationId',
        );
      }

      final organization = await db.query(
        'organizations',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [organizationId],
        limit: 1,
      );
      if (organization.isEmpty) {
        throw StateError(
          'SEC.001 organization identity references a missing organization.',
        );
      }
      return organizationId;
    }

    final organizationId = DatabaseConstants.newUuid();
    final now = DateTime.now().toUtc().toIso8601String();
    final workshop = await db.query(
      'workshop_settings',
      columns: ['workshopName', 'country_code'],
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    final displayName = workshop.isEmpty
        ? null
        : _cleanNullable(workshop.first['workshopName']);
    final countryCode = workshop.isEmpty
        ? null
        : _cleanNullable(workshop.first['country_code'])?.toUpperCase();

    await db.insert('organizations', {
      'id': organizationId,
      'display_name': displayName,
      'country_code': countryCode,
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert('organization_identity', {
      'singleton_id': 1,
      'organization_id': organizationId,
      'created_at': now,
    });

    return organizationId;
  }

  static Future<void> _backfillCurrentScope(
    DatabaseExecutor db,
    String organizationId,
  ) async {
    await db.rawUpdate('''
      UPDATE users
      SET organization_id = ?
      WHERE organization_id IS NULL OR TRIM(organization_id) = ''
    ''', [organizationId]);

    await db.rawUpdate('''
      UPDATE workshop_settings
      SET organization_id = ?
      WHERE organization_id IS NULL OR TRIM(organization_id) = ''
    ''', [organizationId]);
  }

  static Future<void> _createScopeIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_users_organization
      ON users(organization_id);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_workshop_settings_organization
      ON workshop_settings(organization_id);
    ''');
  }

  static Future<void> _createScopeGuards(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_users_org_scope_insert_guard
      BEFORE INSERT ON users
      FOR EACH ROW
      WHEN NEW.organization_id IS NOT NULL
        AND TRIM(NEW.organization_id) <> ''
        AND NEW.organization_id <> (
          SELECT organization_id
          FROM organization_identity
          WHERE singleton_id = 1
        )
      BEGIN
        SELECT RAISE(ABORT, 'organization scope mismatch');
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_users_org_scope_default
      AFTER INSERT ON users
      FOR EACH ROW
      WHEN NEW.organization_id IS NULL OR TRIM(NEW.organization_id) = ''
      BEGIN
        UPDATE users
        SET organization_id = (
          SELECT organization_id
          FROM organization_identity
          WHERE singleton_id = 1
        )
        WHERE id = NEW.id;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_users_org_scope_update_guard
      BEFORE UPDATE OF organization_id ON users
      FOR EACH ROW
      WHEN NEW.organization_id IS NULL
        OR TRIM(NEW.organization_id) = ''
        OR NEW.organization_id <> (
          SELECT organization_id
          FROM organization_identity
          WHERE singleton_id = 1
        )
      BEGIN
        SELECT RAISE(ABORT, 'organization scope mismatch');
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_workshop_org_scope_insert_guard
      BEFORE INSERT ON workshop_settings
      FOR EACH ROW
      WHEN NEW.organization_id IS NOT NULL
        AND TRIM(NEW.organization_id) <> ''
        AND NEW.organization_id <> (
          SELECT organization_id
          FROM organization_identity
          WHERE singleton_id = 1
        )
      BEGIN
        SELECT RAISE(ABORT, 'organization scope mismatch');
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_workshop_org_scope_default
      AFTER INSERT ON workshop_settings
      FOR EACH ROW
      WHEN NEW.organization_id IS NULL OR TRIM(NEW.organization_id) = ''
      BEGIN
        UPDATE workshop_settings
        SET organization_id = (
          SELECT organization_id
          FROM organization_identity
          WHERE singleton_id = 1
        )
        WHERE id = NEW.id;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_workshop_org_scope_update_guard
      BEFORE UPDATE OF organization_id ON workshop_settings
      FOR EACH ROW
      WHEN NEW.organization_id IS NULL
        OR TRIM(NEW.organization_id) = ''
        OR NEW.organization_id <> (
          SELECT organization_id
          FROM organization_identity
          WHERE singleton_id = 1
        )
      BEGIN
        SELECT RAISE(ABORT, 'organization scope mismatch');
      END;
    ''');
  }

  static String? _cleanNullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
      r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}
