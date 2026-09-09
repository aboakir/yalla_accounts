import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';

typedef PermissionDatabaseProvider = Future<Database> Function();

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => PermissionService(),
);

class PermissionService {
  PermissionService({PermissionDatabaseProvider? databaseProvider})
      : _databaseProvider = databaseProvider ?? (() => DBService.database);

  final PermissionDatabaseProvider _databaseProvider;

  Future<bool> hasPermissionForUser(
    String userId,
    String permission,
  ) async {
    if (!PermissionKeys.all.contains(permission)) {
      return false;
    }

    final db = await _databaseProvider();
    if (permission == PermissionKeys.backupRestore) {
      final users = await db.query('users',
          where: 'id = ?', whereArgs: [userId], limit: 1);
      if (users.isEmpty) return false;
      final user = AppUser.fromMap(users.single);
      return user.status == 'active' && user.isOwner;
    }
    final rows = await db.rawQuery(
      '''
      SELECT 1
      FROM users u
      JOIN auth_role_permissions rp ON rp.role_key = lower(trim(u.role))
      WHERE u.id = ?
        AND (u.status IS NULL OR u.status = 'active')
        AND rp.permission_key = ?
      LIMIT 1
      ''',
      [userId, permission],
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> permissionsForUser(String userId) async {
    final db = await _databaseProvider();
    final rows = await db.rawQuery(
      '''
      SELECT rp.permission_key
      FROM users u
      JOIN auth_role_permissions rp ON rp.role_key = lower(trim(u.role))
      WHERE u.id = ?
        AND (u.status IS NULL OR u.status = 'active')
      ORDER BY rp.permission_key
      ''',
      [userId],
    );

    return rows
        .map((row) => row['permission_key']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<bool> canCurrent(String permission) async {
    final actor = await _restoreCurrent();
    if (actor == null) {
      return false;
    }
    return _allowed(actor, permission);
  }

  Future<AppUser> requireCurrent(String permission) async {
    final actor = await _restoreCurrent();
    if (actor == null) {
      throw StateError('Authenticated user session is required.');
    }

    if (!await _allowed(actor, permission)) {
      throw StateError('Permission denied: $permission');
    }

    return actor;
  }

  Future<bool> _allowed(AppUser actor, String permission) async {
    if (AuthSessionService.isRecoverySession) {
      return actor.isOwner &&
          const {PermissionKeys.backupCreate, PermissionKeys.backupExport}
              .contains(permission);
    }
    // Disaster recovery stays Owner-only even if a role permission row is stale.
    if (permission == PermissionKeys.backupRestore) return actor.isOwner;
    if (AuthSessionService.hasPreviewSession) {
      return AuthorizationPolicy.forRole(actor.role).contains(permission);
    }
    return hasPermissionForUser(actor.id, permission);
  }

  Future<void> requireAssignableRole(String role) async {
    if (!RoleKeys.isAssignable(role)) {
      throw StateError('Role is not assignable: $role');
    }

    final db = await _databaseProvider();
    final rows = await db.query(
      'auth_roles',
      columns: ['role_key'],
      where: 'role_key = ? AND is_assignable = 1',
      whereArgs: [role],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Role is not enabled for assignment: $role');
    }
  }

  Future<AppUser?> _restoreCurrent() {
    return AuthSessionService(
      databaseProvider: _databaseProvider,
    ).restoreSession();
  }
}
