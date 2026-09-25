import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/commercial_backend/commercial_backend_environment.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/entitlements/licensed_user_seat_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/owner_bootstrap_tables.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/first_owner_bootstrap_service.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';

typedef UserDatabaseProvider = Future<Database> Function();

final userServiceProvider = Provider(
  (ref) => UserService(enforceActivationForFirstOwner: true),
);

class UserService {
  UserService({
    UserDatabaseProvider? databaseProvider,
    this.enforceActivationForFirstOwner = true,
    this.firstOwnerActivationRepository,
    FirstOwnerBootstrapService? firstOwnerBootstrapService,
    UserSeatEntitlementProvider? userSeatEntitlementProvider,
  })  : _databaseProvider = databaseProvider ?? (() => DBService.database),
        _firstOwnerBootstrapService = firstOwnerBootstrapService,
        _userSeatEntitlementProvider = userSeatEntitlementProvider;

  final UserDatabaseProvider _databaseProvider;
  final bool enforceActivationForFirstOwner;
  final ActivationStateRepository? firstOwnerActivationRepository;
  final FirstOwnerBootstrapService? _firstOwnerBootstrapService;
  final UserSeatEntitlementProvider? _userSeatEntitlementProvider;

  static const int _maxFailedLogins = 5;
  static const Duration _lockoutDuration = Duration(minutes: 15);
  static const Duration _resetGrantLifetime = Duration(minutes: 10);

  static String? validatePasswordPolicy(String password) {
    if (password.length < 10) {
      return 'كلمة المرور يجب أن تكون 10 أحرف على الأقل';
    }

    final hasLetter = RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);

    if (!hasLetter || !hasDigit) {
      return 'استخدم حروفًا وأرقامًا في كلمة المرور';
    }

    return null;
  }

  Future<Database> _db() async => _databaseProvider();

  PermissionService _permissionService() => PermissionService(
        databaseProvider: _databaseProvider,
      );

  UserSeatEntitlementProvider _seatEntitlements() {
    return _userSeatEntitlementProvider ??
        LicensedUserSeatService(
          activationStateRepository: ActivationStateRepository(
            databaseProvider: _databaseProvider,
          ),
        );
  }

  Future<void> _assertActiveSeatAvailable(
    DatabaseExecutor db,
    LicensedUserSeatEntitlement entitlement,
  ) async {
    final mismatched = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM users
      WHERE (status IS NULL OR status = 'active')
        AND (
          organization_id IS NULL
          OR organization_id <> ?
        )
      ''',
      [entitlement.organizationId],
    );
    final mismatchedCount = (mismatched.first['c'] as num?)?.toInt() ?? 0;
    if (mismatchedCount != 0) {
      throw const LicensedUserSeatException(
        'ORGANIZATION_INTEGRITY',
        'Active users are not consistently bound to the licensed organization.',
      );
    }

    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM users
      WHERE (status IS NULL OR status = 'active')
        AND organization_id = ?
      ''',
      [entitlement.organizationId],
    );
    final activeUsers = (rows.first['c'] as num?)?.toInt() ?? 0;
    if (activeUsers >= entitlement.maxUsers) {
      throw LicensedUserSeatException(
        'SEAT_LIMIT_REACHED',
        'The signed license allows ${entitlement.maxUsers} active user seat(s), '
            'and all seats are currently in use.',
      );
    }
  }

  Future<int> _countUsers(Database db) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM users');
    return (r.isNotEmpty ? (r.first['c'] as num?)?.toInt() : 0) ?? 0;
  }

  Future<bool> hasAnyUsers() async {
    final db = await _db();
    return await _countUsers(db) > 0;
  }

  Future<void> ensureOwnerExists() async {
    final db = await _db();

    // Test-only compatibility mode preserves old P1.002 fixtures without
    // weakening the production provider. Production must never manufacture an
    // owner account from an arbitrary pre-existing user.
    if (!enforceActivationForFirstOwner) {
      final owners = await db.query(
        'users',
        columns: ['id'],
        where: 'is_owner = 1',
      );
      if (owners.length == 1) return;
      if (owners.length > 1) {
        throw StateError(
          'Authentication integrity error: more than one owner exists.',
        );
      }
      final count = await _countUsers(db);
      if (count == 0) return;
      throw StateError(
        'Authentication integrity error: users exist without a unique owner.',
      );
    }

    final count = await _countUsers(db);
    if (count == 0) {
      return;
    }

    final owners = await db.query(
      'users',
      columns: ['id', 'organization_id', 'role', 'status'],
      where: 'is_owner = 1',
      limit: 2,
    );
    if (owners.length != 1) {
      throw StateError(
        'Account security integrity error: an existing user set requires '
        'exactly one previously bootstrapped owner.',
      );
    }

    await OwnerBootstrapTables.validate(db);

    final owner = owners.single;
    final ownerId = owner['id']?.toString() ?? '';
    final organizationId = owner['organization_id']?.toString() ?? '';
    if (ownerId.isEmpty ||
        organizationId.isEmpty ||
        owner['role']?.toString() != RoleKeys.owner ||
        owner['status']?.toString() != 'active') {
      throw StateError(
        'Account security integrity error: owner identity is not canonical.',
      );
    }

    final identity = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id = 1',
      limit: 2,
    );
    if (identity.length != 1 ||
        identity.single['organization_id']?.toString() != organizationId) {
      throw StateError(
        'Account security integrity error: owner organization mismatch.',
      );
    }

    final bootstrap = await db.query(
      'owner_bootstrap_state',
      columns: ['status', 'owner_user_id', 'organization_id'],
      where: 'singleton_id = 1',
      limit: 2,
    );
    if (bootstrap.length != 1 ||
        bootstrap.single['status']?.toString() != 'COMPLETED' ||
        bootstrap.single['owner_user_id']?.toString() != ownerId ||
        bootstrap.single['organization_id']?.toString() != organizationId) {
      throw StateError(
        'Account security integrity error: First Owner bootstrap is not '
        'cryptographically and organizationally closed.',
      );
    }
  }

  Future<AppUser?> getOwner() async {
    final db = await _db();
    await ensureOwnerExists();

    final r = await db.query(
      'users',
      where: 'is_owner = 1',
      limit: 1,
    );
    return r.isNotEmpty ? AppUser.fromMap(r.first) : null;
  }

  /// Kept for compatibility with older call sites.
  /// It never creates a default user.
  Future<void> ensureDefaultAccountsExist() async {
    await ensureOwnerExists();
  }

  FirstOwnerBootstrapService _bootstrapService() {
    return _firstOwnerBootstrapService ??
        FirstOwnerBootstrapService(
          databaseProvider: _databaseProvider,
          activationStateRepository: enforceActivationForFirstOwner
              ? firstOwnerActivationRepository
              : null,
        );
  }

  Future<FirstOwnerBootstrapResult> bootstrapFirstOwner(
    FirstOwnerBootstrapRequest request,
  ) {
    return _bootstrapService().createFirstOwner(request);
  }

  /// Compatibility wrapper retained for existing UI call sites.
  /// With no users it performs SEC.007 First Owner bootstrap.
  /// With an existing owner it creates an additional SEC.008 user.
  /// Additional active users are constrained by SEC.009 signed MAX_USERS.
  Future<bool> registerUser(
    AppUser user,
    String password,
  ) async {
    final hasUsers = await hasAnyUsers();

    if (!hasUsers) {
      if (!enforceActivationForFirstOwner) {
        return _registerFirstOwnerForTests(user, password);
      }

      await bootstrapFirstOwner(
        FirstOwnerBootstrapRequest(
          ownerName: user.name,
          password: password,
          email: user.email,
          workshopName: user.workshopName?.trim().isNotEmpty == true
              ? user.workshopName!.trim()
              : 'Yalla Workshop',
          workshopAddress: user.workshopAddress ?? '',
          country: user.country ?? 'فلسطين',
          province: user.province ?? '',
          city: user.city ?? '',
          street: user.street ?? '',
          phone: (user.phoneNumbers?.isNotEmpty ?? false)
              ? user.phoneNumbers!.first
              : 'N/A',
          logoPath: user.workshopLogoPath,
        ),
      );
      return true;
    }

    return createAdditionalUser(user, password);
  }

  Future<bool> createAdditionalUser(
    AppUser user,
    String password,
  ) async {
    final policyError = validatePasswordPolicy(password);
    if (policyError != null) {
      throw ArgumentError(policyError);
    }

    final permissions = _permissionService();
    final actor = await permissions.requireCurrent(PermissionKeys.userCreate);
    await permissions.requireAssignableRole(user.role);
    await permissions.requireCurrent(PermissionKeys.roleManage);

    final name = user.name.trim();
    if (name.isEmpty) {
      throw ArgumentError('User name cannot be empty.');
    }

    const allowedStatuses = {'active', 'inactive', 'frozen'};
    final status =
        allowedStatuses.contains(user.status) ? user.status : 'active';
    final seatEntitlement =
        status == 'active' ? await _seatEntitlements().requireCurrent() : null;
    if (seatEntitlement != null &&
        actor.organizationId != seatEntitlement.organizationId) {
      throw const LicensedUserSeatException(
        'ORGANIZATION_MISMATCH',
        'The signed license does not belong to the current workshop.',
      );
    }

    final db = await _db();
    final now = DateTime.now().toUtc().toIso8601String();
    final targetUserId = const Uuid().v4();
    await db.transaction((txn) async {
      final duplicate = await txn.rawQuery(
        'SELECT 1 FROM users WHERE name = ? COLLATE NOCASE LIMIT 1',
        [name],
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Username already exists.');
      }

      if (seatEntitlement != null) {
        await _assertActiveSeatAvailable(txn, seatEntitlement);
      }

      await txn.insert('users', {
        'id': targetUserId,
        'name': name,
        'email': user.email.trim(),
        'password': PasswordHasher.hash(password),
        'role': user.role,
        'status': status,
        'created_at': now,
        'organization_id': actor.organizationId,
        'is_owner': 0,
        'must_change_password': 1,
        'failed_login_count': 0,
        'locked_until': null,
        'password_changed_at': now,
      });
    });
    await AuditTrailService.log(
      executor: db,
      actorUserId: actor.id,
      actorRole: actor.role,
      action: 'USER_CREATED',
      entityType: 'user',
      entityId: targetUserId,
      after: {
        'name': name,
        'email': user.email.trim(),
        'role': user.role,
        'status': status,
      },
    );

    return true;
  }

  Future<bool> _registerFirstOwnerForTests(
    AppUser user,
    String password,
  ) async {
    final policyError = validatePasswordPolicy(password);
    if (policyError != null) throw ArgumentError(policyError);
    final db = await _db();
    if (await _countUsers(db) > 0) {
      throw StateError('First Owner already exists.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('users', {
      'id': const Uuid().v4(),
      'name': user.name.trim(),
      'email': user.email.trim(),
      'password': PasswordHasher.hash(password),
      'role': 'owner',
      'status': 'active',
      'created_at': now,
      'is_owner': 1,
      'must_change_password': 0,
      'failed_login_count': 0,
      'locked_until': null,
      'password_changed_at': now,
    });
    return true;
  }

  Future<AppUser?> authenticateUser(
    String username,
    String password,
  ) async {
    final db = await _db();
    await ensureOwnerExists();

    final rows = await db.query(
      'users',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [username.trim()],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final row = Map<String, dynamic>.from(rows.first);

    if ((row['status']?.toString() ?? 'active') != 'active') {
      return null;
    }

    final now = DateTime.now().toUtc();
    final lockedUntil = DateTime.tryParse(
      row['locked_until']?.toString() ?? '',
    );

    if (lockedUntil != null && lockedUntil.isAfter(now)) {
      return null;
    }

    final storedPassword = row['password']?.toString() ?? '';
    final verification = PasswordHasher.verify(password, storedPassword);

    if (!verification.isValid) {
      final previous = (row['failed_login_count'] as num?)?.toInt() ?? 0;
      final next = previous + 1;

      await db.update(
        'users',
        {
          'failed_login_count': next,
          'locked_until': next >= _maxFailedLogins
              ? now.add(_lockoutDuration).toIso8601String()
              : null,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );

      return null;
    }

    final updates = <String, Object?>{
      'failed_login_count': 0,
      'locked_until': null,
      'last_login_at': now.toIso8601String(),
    };

    if (verification.needsUpgrade) {
      updates['password'] = PasswordHasher.hash(password);
    }

    await db.update(
      'users',
      updates,
      where: 'id = ?',
      whereArgs: [row['id']],
    );

    final refreshed = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [row['id']],
      limit: 1,
    );

    return refreshed.isNotEmpty ? AppUser.fromMap(refreshed.first) : null;
  }

  Future<AppUser?> getUserById(String id) async {
    final db = await _db();
    final r = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return r.isNotEmpty ? AppUser.fromMap(r.first) : null;
  }

  Future<AppUser?> getUserByUsername(String username) async {
    final db = await _db();
    final r = await db.query(
      'users',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [username.trim()],
      limit: 1,
    );
    return r.isNotEmpty ? AppUser.fromMap(r.first) : null;
  }

  Future<List<AppUser>> getAllUsers() async {
    await _permissionService().requireCurrent(PermissionKeys.userView);
    final db = await _db();
    final r = await db.query('users', orderBy: 'created_at DESC');
    return r
        .map((row) => AppUser.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> updateUser(AppUser user) async {
    final permissions = _permissionService();
    final actor = await permissions.requireCurrent(PermissionKeys.userEdit);
    final db = await _db();
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [user.id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('User does not exist.');
    }

    final target = AppUser.fromMap(rows.first);
    if (target.isOwner && actor.id != target.id) {
      throw StateError(
          'The workshop owner cannot be modified by another user.');
    }

    var nextRole = target.role;
    if (!target.isOwner && user.role != target.role) {
      await permissions.requireCurrent(PermissionKeys.roleManage);
      await permissions.requireAssignableRole(user.role);
      nextRole = user.role;
    }

    var nextStatus = target.status;
    if (!target.isOwner && user.status != target.status) {
      if (user.status == 'active') {
        await permissions.requireCurrent(PermissionKeys.userUnlock);
      } else {
        await permissions.requireCurrent(PermissionKeys.userDisable);
      }
      if (!const {'active', 'inactive', 'frozen'}.contains(user.status)) {
        throw ArgumentError('Unsupported user status: ${user.status}');
      }
      nextStatus = user.status;
    }

    final consumesNewSeat =
        !target.isOwner && target.status != 'active' && nextStatus == 'active';
    final seatEntitlement =
        consumesNewSeat ? await _seatEntitlements().requireCurrent() : null;
    if (seatEntitlement != null &&
        actor.organizationId != seatEntitlement.organizationId) {
      throw const LicensedUserSeatException(
        'ORGANIZATION_MISMATCH',
        'The signed license does not belong to the current workshop.',
      );
    }

    await db.transaction((txn) async {
      if (seatEntitlement != null) {
        await _assertActiveSeatAvailable(txn, seatEntitlement);
      }

      await txn.update(
        'users',
        {
          'name': user.name.trim(),
          'email': user.email.trim(),
          'role': target.isOwner ? RoleKeys.owner : nextRole,
          'status': target.isOwner ? 'active' : nextStatus,
          'is_owner': target.isOwner ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [target.id],
      );
    });

    if (nextRole != target.role || nextStatus != target.status) {
      await AuthSessionService(
        databaseProvider: _databaseProvider,
      ).revokeAllForUser(target.id);
    }
    await AuditTrailService.log(
      executor: db,
      actorUserId: actor.id,
      actorRole: actor.role,
      action: 'USER_UPDATED',
      entityType: 'user',
      entityId: target.id,
      before: {
        'name': target.name,
        'email': target.email,
        'role': target.role,
        'status': target.status,
      },
      after: {
        'name': user.name.trim(),
        'email': user.email.trim(),
        'role': target.isOwner ? RoleKeys.owner : nextRole,
        'status': target.isOwner ? 'active' : nextStatus,
      },
    );
  }

  /// Hard-delete is intentionally disabled. User records are retained for
  /// accounting traceability; this compatibility method performs a soft disable.
  Future<void> deleteUser(String id) async {
    await updateStatus(id, 'frozen');
  }

  Future<void> updateStatus(String id, String status) async {
    if (!const {'active', 'inactive', 'frozen'}.contains(status)) {
      throw ArgumentError('Unsupported user status: $status');
    }

    final permissions = _permissionService();
    final actor = await permissions.requireCurrent(
      status == 'active'
          ? PermissionKeys.userUnlock
          : PermissionKeys.userDisable,
    );

    final db = await _db();
    final rows = await db.query(
      'users',
      columns: ['id', 'is_owner', 'status', 'organization_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('User does not exist.');
    }
    if ((rows.first['is_owner'] as num?)?.toInt() == 1) {
      throw StateError('The workshop owner account cannot be disabled.');
    }

    final previousStatus = rows.first['status']?.toString() ?? 'active';
    final consumesNewSeat = previousStatus != 'active' && status == 'active';
    final seatEntitlement =
        consumesNewSeat ? await _seatEntitlements().requireCurrent() : null;
    if (seatEntitlement != null &&
        actor.organizationId != seatEntitlement.organizationId) {
      throw const LicensedUserSeatException(
        'ORGANIZATION_MISMATCH',
        'The signed license does not belong to the current workshop.',
      );
    }

    await db.transaction((txn) async {
      if (seatEntitlement != null) {
        await _assertActiveSeatAvailable(txn, seatEntitlement);
      }

      await txn.update(
        'users',
        {
          'status': status,
          if (status == 'active') 'failed_login_count': 0,
          if (status == 'active') 'locked_until': null,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    await AuthSessionService(
      databaseProvider: _databaseProvider,
    ).revokeAllForUser(id);
    await AuditTrailService.log(
      executor: db,
      actorUserId: actor.id,
      actorRole: actor.role,
      action: status == 'active' ? 'USER_ENABLED' : 'USER_DISABLED',
      entityType: 'user',
      entityId: id,
      before: {'status': previousStatus},
      after: {'status': status},
    );
  }

  Future<void> changePassword(String id, String newPassword) async {
    throw StateError(
      'Direct password changes are disabled. '
      'Use changeOwnPassword or an authorized reset grant.',
    );
  }

  Future<bool> changeOwnPassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final policyError = validatePasswordPolicy(newPassword);
    if (policyError != null) {
      throw ArgumentError(policyError);
    }

    final actor = await _requireCurrentSession();
    if (actor.id != userId) return false;

    final db = await _db();
    final rows = await db.query(
      'users',
      columns: ['password'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (rows.isEmpty) return false;

    final stored = rows.first['password']?.toString() ?? '';
    if (!PasswordHasher.verify(currentPassword, stored).isValid) {
      return false;
    }

    await db.update(
      'users',
      {
        'password': PasswordHasher.hash(newPassword),
        'must_change_password': 0,
        'password_changed_at': DateTime.now().toUtc().toIso8601String(),
        'failed_login_count': 0,
        'locked_until': null,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );

    await AuthSessionService(
      databaseProvider: _databaseProvider,
    ).revokeAllForUser(userId);
    await AuditTrailService.log(
      executor: db,
      actorUserId: actor.id,
      actorRole: actor.role,
      action: 'PASSWORD_CHANGED',
      entityType: 'user',
      entityId: userId,
    );

    return true;
  }

  Future<void> resetUserPasswordByOwner({
    required String userId,
    required String temporaryPassword,
  }) async {
    final policyError = validatePasswordPolicy(temporaryPassword);
    if (policyError != null) {
      throw ArgumentError(policyError);
    }

    final actor = await _requireOwnerSession();
    final db = await _db();
    final rows = await db.query(
      'users',
      columns: ['id', 'is_owner', 'organization_id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('User does not exist.');
    }

    final row = rows.single;
    if ((row['is_owner'] as num?)?.toInt() == 1 || userId == actor.id) {
      throw StateError(
        'The workshop owner password must use the owner recovery flow.',
      );
    }

    final targetOrganizationId = row['organization_id']?.toString();
    if (actor.organizationId != null &&
        targetOrganizationId != null &&
        actor.organizationId != targetOrganizationId) {
      throw StateError('User belongs to another organization.');
    }

    await db.update(
      'users',
      {
        'password': PasswordHasher.hash(temporaryPassword),
        'must_change_password': 1,
        'password_changed_at': DateTime.now().toUtc().toIso8601String(),
        'failed_login_count': 0,
        'locked_until': null,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );

    await AuthSessionService(
      databaseProvider: _databaseProvider,
    ).revokeAllForUser(userId);
    await AuditTrailService.log(
      executor: db,
      actorUserId: actor.id,
      actorRole: actor.role,
      action: 'PASSWORD_RESET_BY_OWNER',
      entityType: 'user',
      entityId: userId,
    );
  }

  Future<bool> verifyOwnerPassword(String password) async {
    final owner = await getOwner();
    if (owner == null) return false;

    final db = await _db();
    final rows = await db.query(
      'users',
      columns: ['password'],
      where: 'id = ?',
      whereArgs: [owner.id],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    return PasswordHasher.verify(
      password,
      rows.first['password']?.toString() ?? '',
    ).isValid;
  }

  Future<bool> verifySecurityAnswers({
    required String answer1,
    required String answer2,
  }) async {
    final owner = await getOwner();
    if (owner == null || owner.securityAnswerHash == null) return false;

    final combined = '${answer1.trim()}|${answer2.trim()}';
    final verification = PasswordHasher.verify(
      combined,
      owner.securityAnswerHash!,
    );

    if (verification.isValid && verification.needsUpgrade) {
      final db = await _db();
      await db.update(
        'users',
        {'security_answer_hash': PasswordHasher.hash(combined)},
        where: 'id = ?',
        whereArgs: [owner.id],
      );
    }

    return verification.isValid;
  }

  Future<void> setSecurityQuestions({
    required String question1,
    required String question2,
    required String answer1,
    required String answer2,
    String? currentPassword,
  }) async {
    final actor = await _requireOwnerReauthentication(currentPassword);
    final combinedAnswer = '${answer1.trim()}|${answer2.trim()}';

    if (answer1.trim().isEmpty || answer2.trim().isEmpty) {
      throw ArgumentError('Security answers cannot be empty.');
    }

    final db = await _db();
    await db.update(
      'users',
      {
        'security_question': '$question1 | $question2',
        'security_answer_hash': PasswordHasher.hash(combinedAnswer),
      },
      where: 'id = ?',
      whereArgs: [actor.id],
    );
  }

  Future<bool> resetPassword({
    required String userId,
    required String newPassword,
  }) async {
    throw StateError(
      'Direct password reset is disabled. '
      'A one-time recovery grant is required.',
    );
  }

  Future<bool> resetOwnerPassword(String newPassword) async {
    throw StateError(
      'Direct owner reset is disabled. '
      'Use a one-time recovery grant.',
    );
  }

  Future<bool> resetOwnerPasswordAfterVerifiedEmail({
    required String newPassword,
    required bool backendAuthorized,
  }) async {
    if (!backendAuthorized ||
        !CommercialBackendEnvironment.enabled ||
        !CommercialBackendRuntimeAccess.canRead) {
      return false;
    }
    final policyError = validatePasswordPolicy(newPassword);
    if (policyError != null) {
      throw ArgumentError(policyError);
    }
    final owner = await getOwner();
    if (owner == null) return false;

    final db = await _db();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {
        'password': PasswordHasher.hash(newPassword),
        'must_change_password': 0,
        'password_changed_at': now,
        'failed_login_count': 0,
        'locked_until': null,
      },
      where: 'id = ?',
      whereArgs: [owner.id],
    );

    await AuthSessionService(
      databaseProvider: _databaseProvider,
    ).revokeAllForUser(owner.id);
    return true;
  }

  Future<bool> changeOwnerUsername(
    String newUsername, {
    String? currentPassword,
  }) async {
    final actor = await _requireOwnerReauthentication(currentPassword);
    final trimmed = newUsername.trim();
    if (trimmed.isEmpty) return false;

    final db = await _db();
    final exists = await db.rawQuery(
      'SELECT 1 FROM users '
      'WHERE name = ? COLLATE NOCASE AND id != ? LIMIT 1',
      [trimmed, actor.id],
    );
    if (exists.isNotEmpty) return false;

    await db.update(
      'users',
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [actor.id],
    );
    return true;
  }

  String _generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();

    String block() {
      return List.generate(
        4,
        (_) => chars[rnd.nextInt(chars.length)],
      ).join();
    }

    return 'YA-${block()}-${block()}';
  }

  Future<String?> generateOwnerRecoveryCode({
    String? currentPassword,
  }) async {
    final actor = await _requireOwnerReauthentication(currentPassword);
    final code = _generateRecoveryCode();
    final db = await _db();

    await db.update(
      'users',
      {
        'recovery_code_hash': PasswordHasher.hash(code),
        'recovery_code_used': 0,
      },
      where: 'id = ?',
      whereArgs: [actor.id],
    );

    return code;
  }

  Future<bool> verifyRecoveryCode(String code) async {
    final owner = await getOwner();
    if (owner == null) return false;

    final db = await _db();
    final r = await db.query(
      'users',
      columns: ['recovery_code_hash', 'recovery_code_used'],
      where: 'id = ?',
      whereArgs: [owner.id],
      limit: 1,
    );

    if (r.isEmpty) return false;

    final hash = r.first['recovery_code_hash']?.toString();
    final used = (r.first['recovery_code_used'] as num?)?.toInt() ?? 0;

    if (hash == null || used == 1) return false;

    return PasswordHasher.verify(code.trim(), hash).isValid;
  }

  Future<void> consumeRecoveryCode() async {
    final owner = await getOwner();
    if (owner == null) return;

    final db = await _db();
    await db.update(
      'users',
      {'recovery_code_used': 1},
      where: 'id = ?',
      whereArgs: [owner.id],
    );
  }

  Future<String?> createResetGrantWithSecurityAnswers({
    required String answer1,
    required String answer2,
  }) async {
    if (!await verifySecurityAnswers(
      answer1: answer1,
      answer2: answer2,
    )) {
      return null;
    }

    final owner = await getOwner();
    if (owner == null) return null;
    return _issuePasswordResetGrant(owner.id);
  }

  Future<String?> createResetGrantWithRecoveryCode(
    String code,
  ) async {
    final owner = await getOwner();
    if (owner == null) return null;

    final db = await _db();
    final rows = await db.query(
      'users',
      columns: ['recovery_code_hash', 'recovery_code_used'],
      where: 'id = ?',
      whereArgs: [owner.id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final stored = rows.first['recovery_code_hash']?.toString();
    final used = (rows.first['recovery_code_used'] as num?)?.toInt() ?? 0;

    if (stored == null || used == 1) return null;
    if (!PasswordHasher.verify(code.trim(), stored).isValid) {
      return null;
    }

    final grant = await _issuePasswordResetGrant(owner.id);

    await db.update(
      'users',
      {'recovery_code_used': 1},
      where: 'id = ?',
      whereArgs: [owner.id],
    );

    return grant;
  }

  Future<bool> resetPasswordWithGrant({
    required String grantToken,
    required String newPassword,
  }) async {
    final policyError = validatePasswordPolicy(newPassword);
    if (policyError != null) {
      throw ArgumentError(policyError);
    }

    final db = await _db();
    final now = DateTime.now().toUtc();
    final tokenHash = _tokenHash(grantToken);

    String? userId;

    await db.transaction((txn) async {
      final grants = await txn.query(
        'password_reset_grants',
        where: 'token_hash = ? '
            'AND used_at IS NULL '
            'AND expires_at > ?',
        whereArgs: [tokenHash, now.toIso8601String()],
        limit: 1,
      );

      if (grants.isEmpty) return;

      userId = grants.first['user_id']?.toString();
      if (userId == null || userId!.isEmpty) return;

      await txn.update(
        'users',
        {
          'password': PasswordHasher.hash(newPassword),
          'must_change_password': 0,
          'password_changed_at': now.toIso8601String(),
          'failed_login_count': 0,
          'locked_until': null,
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      await txn.update(
        'password_reset_grants',
        {'used_at': now.toIso8601String()},
        where: 'token_hash = ?',
        whereArgs: [tokenHash],
      );
    });

    if (userId == null) return false;

    await AuthSessionService(
      databaseProvider: _databaseProvider,
    ).revokeAllForUser(userId!);

    return true;
  }

  Future<bool> verifySecurityAnswer(String answer) async {
    return verifySecurityAnswers(
      answer1: answer,
      answer2: '',
    );
  }

  Future<AppUser> _requireCurrentSession() async {
    final session = AuthSessionService(
      databaseProvider: _databaseProvider,
    );
    final actor = await session.restoreSession();

    if (actor == null || actor.status != 'active') {
      throw StateError('Authenticated user session is required.');
    }

    return actor;
  }

  Future<AppUser> _requireOwnerSession() async {
    final session = AuthSessionService(
      databaseProvider: _databaseProvider,
    );
    final actor = await session.restoreSession();

    if (actor == null || actor.status != 'active' || !actor.isOwner) {
      throw StateError('Owner authentication is required.');
    }

    return actor;
  }

  Future<AppUser> _requireOwnerReauthentication(
    String? currentPassword,
  ) async {
    if (currentPassword == null || currentPassword.isEmpty) {
      throw StateError(
        'Current owner password is required for this security change.',
      );
    }

    final actor = await _requireOwnerSession();
    final db = await _db();
    final rows = await db.query(
      'users',
      columns: ['password'],
      where: 'id = ?',
      whereArgs: [actor.id],
      limit: 1,
    );
    if (rows.length != 1 ||
        !PasswordHasher.verify(
          currentPassword,
          rows.single['password']?.toString() ?? '',
        ).isValid) {
      throw StateError(
        'Current owner password is required for this security change.',
      );
    }
    return actor;
  }

  Future<String> _issuePasswordResetGrant(String userId) async {
    final db = await _db();
    final now = DateTime.now().toUtc();
    final rawToken = _newSecureToken();

    await db.transaction((txn) async {
      // There may be only one live recovery authority per account. Issuing a
      // new grant revokes every older unused grant, preventing parallel reset
      // links from remaining valid.
      await txn.update(
        'password_reset_grants',
        {'used_at': now.toIso8601String()},
        where: 'user_id = ? AND used_at IS NULL',
        whereArgs: [userId],
      );

      await txn.insert('password_reset_grants', {
        'id': const Uuid().v4(),
        'user_id': userId,
        'token_hash': _tokenHash(rawToken),
        'created_at': now.toIso8601String(),
        'expires_at': now.add(_resetGrantLifetime).toIso8601String(),
        'used_at': null,
      });
    });

    return rawToken;
  }

  static String _newSecureToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    );
    return base64UrlEncode(bytes);
  }

  static String _tokenHash(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }
}
