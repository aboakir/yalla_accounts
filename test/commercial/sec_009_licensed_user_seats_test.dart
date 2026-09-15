import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/entitlements/licensed_user_seat_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

class _FixedSeatProvider implements UserSeatEntitlementProvider {
  const _FixedSeatProvider(this.entitlement);

  final LicensedUserSeatEntitlement entitlement;

  @override
  Future<LicensedUserSeatEntitlement> requireCurrent() async => entitlement;
}

class _FakeActivationStateRepository extends ActivationStateRepository {
  _FakeActivationStateRepository(this.license);

  final VerifiedLicense? license;

  @override
  Future<VerifiedLicense?> loadVerifiedLicenseForCurrentInstallation() async {
    return license;
  }
}

VerifiedLicense _license({
  required String organizationId,
  Object? maxUsers = 2,
}) {
  final now = DateTime.now().toUtc();
  return VerifiedLicense(
    licenseId: '11111111-1111-4111-8111-111111111111',
    organizationId: organizationId,
    subscriptionId: '22222222-2222-4222-8222-222222222222',
    deviceId: '33333333-3333-4333-8333-333333333333',
    installationId: '44444444-4444-4444-8444-444444444444',
    issuedAt: now,
    notBefore: now.subtract(const Duration(seconds: 1)),
    expiresAt: now.add(const Duration(days: 30)),
    entitlementRevision: 9,
    entitlements: <String, Object?>{
      'MAX_USERS': maxUsers,
      'MAX_DEVICES': 2,
    },
    validationRequiredAt: now.add(const Duration(days: 30)),
    validationGraceUntil: now.add(const Duration(days: 37)),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SEC.009 reads MAX_USERS only from a verified license object', () async {
    const organizationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final service = LicensedUserSeatService(
      activationStateRepository: _FakeActivationStateRepository(
        _license(organizationId: organizationId, maxUsers: 5),
      ),
    );

    final entitlement = await service.requireCurrent();
    expect(entitlement.organizationId, organizationId);
    expect(entitlement.maxUsers, 5);
    expect(entitlement.entitlementRevision, 9);

    final missing = LicensedUserSeatService(
      activationStateRepository: _FakeActivationStateRepository(null),
    );
    await expectLater(
      missing.requireCurrent(),
      throwsA(
        isA<LicensedUserSeatException>().having(
          (e) => e.code,
          'code',
          'SIGNED_LICENSE_REQUIRED',
        ),
      ),
    );

    final invalid = LicensedUserSeatService(
      activationStateRepository: _FakeActivationStateRepository(
        _license(organizationId: organizationId, maxUsers: '999'),
      ),
    );
    await expectLater(
      invalid.requireCurrent(),
      throwsA(
        isA<LicensedUserSeatException>().having(
          (e) => e.code,
          'code',
          'INVALID_MAX_USERS',
        ),
      ),
    );
  });

  test('SEC.009 enforces active seats on create and reactivation', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec009_seats_');
    final path = '${temp.path}${Platform.pathSeparator}seats.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    Future<sq.Database> provider() async => db;

    try {
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(67));
      final organizationId = (await db.query(
        'organization_identity',
        columns: ['organization_id'],
        where: 'singleton_id = 1',
      ))
          .single['organization_id']!
          .toString();
      final now = DateTime.now().toUtc().toIso8601String();
      const ownerId = '55555555-5555-4555-8555-555555555555';

      await db.insert('users', {
        'id': ownerId,
        'name': 'owner009',
        'email': 'owner009@example.test',
        'password': PasswordHasher.hash('OwnerPass009'),
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

      final seats = _FixedSeatProvider(
        LicensedUserSeatEntitlement(
          organizationId: organizationId,
          licenseId: '66666666-6666-4666-8666-666666666666',
          subscriptionId: '77777777-7777-4777-8777-777777777777',
          entitlementRevision: 12,
          maxUsers: 2,
        ),
      );
      final users = UserService(
        databaseProvider: provider,
        userSeatEntitlementProvider: seats,
      );

      await users.createAdditionalUser(
        AppUser(
          id: '',
          name: 'employee009',
          email: '',
          role: RoleKeys.staff,
          status: 'active',
          createdAt: DateTime.now(),
        ),
        'CashierPass009',
      );

      await expectLater(
        users.createAdditionalUser(
          AppUser(
            id: '',
            name: 'blocked009',
            email: '',
            role: RoleKeys.viewer,
            status: 'active',
            createdAt: DateTime.now(),
          ),
          'BlockedPass009',
        ),
        throwsA(
          isA<LicensedUserSeatException>().having(
            (e) => e.code,
            'code',
            'SEAT_LIMIT_REACHED',
          ),
        ),
      );

      await users.createAdditionalUser(
        AppUser(
          id: '',
          name: 'frozen009',
          email: '',
          role: RoleKeys.viewer,
          status: 'frozen',
          createdAt: DateTime.now(),
        ),
        'FrozenPass009',
      );
      final frozen = (await db.query(
        'users',
        where: 'name = ?',
        whereArgs: ['frozen009'],
      ))
          .single;

      await expectLater(
        users.updateStatus(frozen['id']!.toString(), 'active'),
        throwsA(
          isA<LicensedUserSeatException>().having(
            (e) => e.code,
            'code',
            'SEAT_LIMIT_REACHED',
          ),
        ),
      );

      final employee = (await db.query(
        'users',
        where: 'name = ?',
        whereArgs: ['employee009'],
      ))
          .single;
      await users.updateStatus(employee['id']!.toString(), 'frozen');
      await users.updateStatus(frozen['id']!.toString(), 'active');

      final active = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM users WHERE status = 'active'",
      );
      expect((active.single['c'] as num).toInt(), 2);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).first.values.first,
        'ok',
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
