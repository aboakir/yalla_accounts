import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/licensing/entitlements/licensed_user_seat_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

class _Sec008UnlimitedSeatProvider implements UserSeatEntitlementProvider {
  const _Sec008UnlimitedSeatProvider(this.organizationId);

  final String organizationId;

  @override
  Future<LicensedUserSeatEntitlement> requireCurrent() async {
    return LicensedUserSeatEntitlement(
      organizationId: organizationId,
      licenseId: '88888888-8888-4888-8888-888888888888',
      subscriptionId: '99999999-9999-4999-8999-999999999999',
      entitlementRevision: 1,
      maxUsers: 999,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SEC.008 seeds canonical roles and permissions', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec008_policy_');
    final path = '${temp.path}${Platform.pathSeparator}policy.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(67));
      expect((await db.query('auth_roles')).length, RoleKeys.all.length);
      expect(
        (await db.query('auth_permissions')).length,
        PermissionKeys.all.length,
      );

      final ownerPermissions = await db.query(
        'auth_role_permissions',
        where: 'role_key = ?',
        whereArgs: [RoleKeys.owner],
      );
      expect(ownerPermissions.length, PermissionKeys.all.length);

      final readOnlyPermissions = await db.query(
        'auth_role_permissions',
        columns: ['permission_key'],
        where: 'role_key = ?',
        whereArgs: [RoleKeys.readOnly],
      );
      final readOnlyKeys = readOnlyPermissions
          .map((row) => row['permission_key']?.toString())
          .whereType<String>()
          .toSet();
      expect(readOnlyKeys, contains(PermissionKeys.reportView));
      expect(readOnlyKeys, isNot(contains(PermissionKeys.invoicePost)));
      expect(readOnlyKeys, isNot(contains(PermissionKeys.userCreate)));
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('SEC.008 owner can create user and non-owner cannot self-escalate',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec008_users_');
    final path = '${temp.path}${Platform.pathSeparator}users.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    Future<sq.Database> provider() async => db;

    try {
      final organizationId = (await db.query(
        'organization_identity',
        columns: ['organization_id'],
        where: 'singleton_id = 1',
      ))
          .single['organization_id']!
          .toString();
      final now = DateTime.now().toUtc().toIso8601String();
      const ownerId = '11111111-1111-4111-8111-111111111111';

      await db.insert('users', {
        'id': ownerId,
        'name': 'owner008',
        'email': 'owner008@example.test',
        'password': PasswordHasher.hash('OwnerPass008'),
        'role': RoleKeys.owner,
        'status': 'active',
        'created_at': now,
        'organization_id': organizationId,
        'is_owner': 1,
        'must_change_password': 0,
        'failed_login_count': 0,
      });

      final owner = AppUser.fromMap((await db.query('users')).single);
      await AuthSessionService(databaseProvider: provider).createSession(owner);

      final service = UserService(
        databaseProvider: provider,
        userSeatEntitlementProvider:
            _Sec008UnlimitedSeatProvider(organizationId),
      );
      await service.createAdditionalUser(
        AppUser(
          id: '',
          name: 'cashier008',
          email: 'cashier008@example.test',
          role: RoleKeys.cashier,
          status: 'active',
          createdAt: DateTime.now(),
        ),
        'CashierPass008',
      );

      final cashierRow = (await db.query(
        'users',
        where: 'name = ?',
        whereArgs: ['cashier008'],
      ))
          .single;
      expect(cashierRow['role'], RoleKeys.cashier);
      expect(cashierRow['is_owner'], 0);
      expect(cashierRow['must_change_password'], 1);
      expect(
        PasswordHasher.verify(
          'CashierPass008',
          cashierRow['password']!.toString(),
        ).isValid,
        isTrue,
      );

      final permissions = PermissionService(databaseProvider: provider);
      expect(
        await permissions.hasPermissionForUser(
          cashierRow['id']!.toString(),
          PermissionKeys.receiptCreate,
        ),
        isTrue,
      );
      expect(
        await permissions.hasPermissionForUser(
          cashierRow['id']!.toString(),
          PermissionKeys.userCreate,
        ),
        isFalse,
      );

      final cashier = AppUser.fromMap(cashierRow);
      await AuthSessionService(databaseProvider: provider)
          .createSession(cashier);
      await expectLater(
        service.createAdditionalUser(
          AppUser(
            id: '',
            name: 'forbidden008',
            email: '',
            role: RoleKeys.manager,
            status: 'active',
            createdAt: DateTime.now(),
          ),
          'Forbidden008',
        ),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        db.insert('users', {
          'id': '33333333-3333-4333-8333-333333333333',
          'name': 'invalid-role',
          'password': PasswordHasher.hash('InvalidPass008'),
          'role': 'super_admin',
          'status': 'active',
          'created_at': now,
          'organization_id': organizationId,
          'is_owner': 0,
        }),
        throwsA(anything),
      );

      expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first,
          'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
