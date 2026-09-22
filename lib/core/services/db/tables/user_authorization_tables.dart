import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';

class UserAuthorizationTables {
  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auth_roles (
        role_key TEXT PRIMARY KEY,
        display_name_ar TEXT NOT NULL,
        is_system INTEGER NOT NULL DEFAULT 1 CHECK(is_system IN (0, 1)),
        is_assignable INTEGER NOT NULL DEFAULT 1 CHECK(is_assignable IN (0, 1)),
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS auth_permissions (
        permission_key TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS auth_role_permissions (
        role_key TEXT NOT NULL,
        permission_key TEXT NOT NULL,
        PRIMARY KEY(role_key, permission_key),
        FOREIGN KEY(role_key) REFERENCES auth_roles(role_key) ON DELETE CASCADE,
        FOREIGN KEY(permission_key) REFERENCES auth_permissions(permission_key)
          ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auth_role_permissions_permission
      ON auth_role_permissions(permission_key, role_key);
    ''');

    await refreshRoleCatalog(db);
    await _normalizeHistoricalRoles(db);
    await _ensureUserRoleTriggers(db);
  }

  /// Update policy metadata without rewriting existing user identities/roles.
  static Future<void> refreshRoleCatalog(DatabaseExecutor db) async {
    await _seedRoles(db);
    await _seedPermissions(db);
    await _seedRolePermissions(db);
  }

  static Future<void> _seedRoles(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final role in RoleKeys.all) {
      await db.insert(
        'auth_roles',
        {
          'role_key': role,
          'display_name_ar': RoleKeys.displayNameAr(role),
          'is_system': 1,
          'is_assignable': RoleKeys.isAssignable(role) ? 1 : 0,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      // Existing installations may already have this role from SEC.008.
      // Keep its metadata synchronized with the P16 policy without replacing
      // the row (REPLACE could cascade role-permission rows).
      await db.update(
        'auth_roles',
        {
          'display_name_ar': RoleKeys.displayNameAr(role),
          'is_system': 1,
          'is_assignable': RoleKeys.isAssignable(role) ? 1 : 0,
        },
        where: 'role_key = ?',
        whereArgs: [role],
      );
    }
  }

  static Future<void> _seedPermissions(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final permission in PermissionKeys.all) {
      await db.insert(
        'auth_permissions',
        {
          'permission_key': permission,
          'category': _categoryFor(permission),
          'description': permission,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<void> _seedRolePermissions(DatabaseExecutor db) async {
    for (final entry in AuthorizationPolicy.rolePermissions.entries) {
      // P16 role permissions are canonical. Remove stale grants left by older
      // policy versions before inserting the current matrix.
      await db.delete(
        'auth_role_permissions',
        where: 'role_key = ?',
        whereArgs: [entry.key],
      );
      for (final permission in entry.value) {
        await db.insert(
          'auth_role_permissions',
          {
            'role_key': entry.key,
            'permission_key': permission,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  static Future<void> _normalizeHistoricalRoles(DatabaseExecutor db) async {
    await db.execute('''
      UPDATE users
      SET role = '${RoleKeys.owner}'
      WHERE is_owner = 1;
    ''');

    await db.execute('''
      UPDATE users
      SET role = '${RoleKeys.manager}'
      WHERE COALESCE(is_owner, 0) = 0
        AND LOWER(COALESCE(role, '')) IN ('manager');
    ''');

    await db.execute('''
      UPDATE users
      SET role = '${RoleKeys.readOnly}'
      WHERE COALESCE(is_owner, 0) = 0
        AND LOWER(COALESCE(role, '')) NOT IN (
          'admin', 'staff', 'viewer',
          '${RoleKeys.manager}',
          '${RoleKeys.accountant}',
          '${RoleKeys.employee}',
          '${RoleKeys.technician}',
          '${RoleKeys.cashier}',
          '${RoleKeys.workshopManager}',
          '${RoleKeys.estimator}',
          '${RoleKeys.storekeeper}',
          '${RoleKeys.auditor}',
          '${RoleKeys.readOnly}'
        );
    ''');
  }

  static Future<void> _ensureUserRoleTriggers(DatabaseExecutor db) async {
    await db.execute('DROP TRIGGER IF EXISTS trg_users_role_valid_insert;');
    await db.execute('DROP TRIGGER IF EXISTS trg_users_role_valid_update;');
    await db.execute('DROP TRIGGER IF EXISTS trg_users_owner_role_insert;');
    await db.execute('DROP TRIGGER IF EXISTS trg_users_owner_role_update;');

    await db.execute('''
      CREATE TRIGGER trg_users_role_valid_insert
      BEFORE INSERT ON users
      WHEN NEW.role IS NULL
        OR NOT EXISTS (
          SELECT 1 FROM auth_roles r WHERE r.role_key = NEW.role
        )
      BEGIN
        SELECT RAISE(ABORT, 'SEC.008 unknown user role');
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER trg_users_role_valid_update
      BEFORE UPDATE OF role ON users
      WHEN NEW.role IS NULL
        OR NOT EXISTS (
          SELECT 1 FROM auth_roles r WHERE r.role_key = NEW.role
        )
      BEGIN
        SELECT RAISE(ABORT, 'SEC.008 unknown user role');
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER trg_users_owner_role_insert
      BEFORE INSERT ON users
      WHEN (COALESCE(NEW.is_owner, 0) = 1 AND NEW.role != '${RoleKeys.owner}')
        OR (NEW.role = '${RoleKeys.owner}' AND COALESCE(NEW.is_owner, 0) != 1)
      BEGIN
        SELECT RAISE(ABORT, 'SEC.008 owner role invariant');
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER trg_users_owner_role_update
      BEFORE UPDATE OF role, is_owner ON users
      WHEN (COALESCE(NEW.is_owner, 0) = 1 AND NEW.role != '${RoleKeys.owner}')
        OR (NEW.role = '${RoleKeys.owner}' AND COALESCE(NEW.is_owner, 0) != 1)
      BEGIN
        SELECT RAISE(ABORT, 'SEC.008 owner role invariant');
      END;
    ''');
  }

  static String _categoryFor(String permission) {
    if (permission.startsWith('CUSTOMER_')) {
      return 'CUSTOMER';
    }
    if (permission.startsWith('REPAIR_')) {
      return 'REPAIR';
    }
    if (permission.startsWith('INVOICE_')) {
      return 'INVOICE';
    }
    if (permission.startsWith('INSURANCE_')) {
      return 'INSURANCE';
    }
    if (permission.startsWith('RECEIPT_') ||
        permission.startsWith('PAYMENT_')) {
      return 'CASH';
    }
    if (permission.startsWith('GL_')) {
      return 'GL';
    }
    if (permission.startsWith('REPORT_')) {
      return 'REPORT';
    }
    if (permission.startsWith('USER_') ||
        permission == PermissionKeys.roleManage) {
      return 'USER_ADMIN';
    }
    if (permission.startsWith('PERIOD_')) {
      return 'PERIOD';
    }
    if (permission.startsWith('SETTINGS_')) {
      return 'SETTINGS';
    }
    if (permission.startsWith('BACKUP_') ||
        permission == PermissionKeys.windowsImport) {
      return 'BACKUP';
    }
    if (permission == PermissionKeys.auditView) {
      return 'AUDIT';
    }
    if (permission.startsWith('CHEQUE_')) return 'CHEQUE';
    if (permission.startsWith('PURCHASE_')) return 'PURCHASE';
    if (permission.startsWith('PAYROLL_')) return 'PAYROLL';
    return 'OTHER';
  }
}
