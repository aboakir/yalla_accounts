import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/identity_account_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/owner_bootstrap_tables.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/features/auth/models/identity_account.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/services/device_unlock_service.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'stage46_subscription_access_test.dart' as licensing;

Future<void> addUser(Database db, String role) async {
  await db.insert('users', {
    'id': role,
    'name': role,
    'email': '$role@example.invalid',
    'password': PasswordHasher.hash('Local-Password123!'),
    'role': role,
    'is_owner': role == 'owner' ? 1 : 0,
    'status': 'active',
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() {
    AuthSessionService.resetProcessMemoryForTesting();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(AuthSessionService.resetProcessMemoryForTesting);

  test('v71 readonly upgrade preserves data, roles, identities and UUIDs',
      () async {
    final dir = await Directory.systemTemp.createTemp('identity_upgrade_');
    final path = '${dir.path}/fixture.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      for (final role in ['owner', 'manager', 'technician']) {
        await addUser(db, role);
      }
      await OwnerBootstrapTables.ensure(db);
      await db.insert('clients', {'name': 'عميل محفوظ', 'type': 'individual'});
      final original = await db.query('users');
      final accountsBefore = await db.query('accounts');
      final organizationBefore = await db.query('organizations');
      // Construct an isolated v71 fixture: remove only the additive v72 schema.
      await db.execute('DROP TRIGGER trg_users_identity_create');
      await db.execute('DROP TRIGGER trg_users_identity_immutable');
      await db.execute('DROP INDEX idx_users_identity_account');
      await db.execute('ALTER TABLE users DROP COLUMN identity_account_id');
      await db.execute('DROP TABLE identity_accounts');
      await db.delete('schema_migrations', where: 'version = 72');
      await db.update('license_runtime_state', {'mode': 'READ_ONLY_EXPIRED'});
      await db.setVersion(71);
      await db.execute(
          "CREATE TRIGGER reject_identity_migration BEFORE INSERT ON schema_migrations "
          "WHEN NEW.version = 72 BEGIN SELECT RAISE(ABORT, 'interrupted migration'); END");
      await db.close();
      await expectLater(DatabaseMigration.initDatabase(pathOverride: path),
          throwsA(anything));
      db = await databaseFactoryFfi.openDatabase(path);
      expect(await db.getVersion(), 71);
      expect(
          await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE name = 'identity_accounts'"),
          isEmpty);
      expect((await db.query('users')).map((r) => r['role']),
          ['owner', 'manager', 'technician']);
      await db.execute('DROP TRIGGER reject_identity_migration');
      await db.close();
      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      final migrated = await db.query('users');
      for (var i = 0; i < original.length; i++) {
        for (final entry in original[i].entries) {
          if (entry.key != 'identity_account_id') {
            expect(migrated[i][entry.key], entry.value, reason: entry.key);
          }
        }
      }
      final people = await db.query('identity_accounts');
      expect(people, hasLength(3));
      expect(people.map((row) => row['id']).toSet(), hasLength(3));
      for (final row in people) {
        final person = IdentityAccount.fromMap(row);
        expect(
            person.id,
            matches(RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      }
      expect(await db.query('accounts'), accountsBefore);
      expect(await db.query('organizations'), organizationBefore);
      expect((await db.query('clients')).single['name'], 'عميل محفوظ');
      await expectLater(
          db.insert('clients', {'name': 'blocked'}), throwsA(anything));
      await expectLater(
          db.update('users', {'identity_account_id': null}), throwsA(anything));
      await expectLater(db.delete('identity_accounts'), throwsA(anything));
      await IdentityAccountTables.ensure(db);
      await db.close();
      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.query('identity_accounts'), people);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(await db.query('schema_migrations', where: 'version = 72'),
          hasLength(1));
    } finally {
      await db.close();
    }
  });

  test(
      'new users get distinct person accounts and transaction rollback leaves no orphan',
      () async {
    final dir = await Directory.systemTemp.createTemp('identity_atomic_');
    final db =
        await DatabaseMigration.initDatabase(pathOverride: '${dir.path}/db');
    try {
      await addUser(db, 'owner');
      final before = await db.query('identity_accounts');
      await expectLater(db.transaction((txn) async {
        await txn.insert('users', {
          'id': 'rolled-back',
          'name': 'staff',
          'password': 'fixture',
          'role': 'staff',
          'status': 'active',
          'created_at': DateTime.now().toIso8601String()
        });
        throw StateError('simulated interruption');
      }), throwsStateError);
      expect(await db.query('identity_accounts'), before);
      expect(await db.query('users'), hasLength(1));
      await addUser(db, 'staff');
      expect(await db.query('identity_accounts'), hasLength(2));
      await expectLater(
          db.update('users', {'identity_account_id': before.single['id']},
              where: 'id = ?', whereArgs: ['staff']),
          throwsA(anything));
      await expectLater(
          db.delete('identity_accounts',
              where: 'id = ?', whereArgs: [before.single['id']]),
          throwsA(anything));
    } finally {
      await db.close();
    }
  });

  for (final status in [
    'ACTIVE',
    'TRIAL',
    'GRACE',
    'EXPIRED',
    'FROZEN',
    'CANCELLED',
    'EXCEPTION',
    'DEMO'
  ]) {
    test('offline restart PIN and all five roles enforce $status', () async {
      await HttpOverrides.runZoned(() async {
        final dir = await Directory.systemTemp.createTemp('offline_identity_');
        final path = '${dir.path}/db';
        var db = await DatabaseMigration.initDatabase(pathOverride: path);
        try {
          for (final role in RoleKeys.canonical) {
            await addUser(db, role);
          }
          await OwnerBootstrapTables.ensure(db);
          final org = (await db.query('organizations')).single['id'] as String;
          final repo = licensing.Repository()
            ..value = licensing.license(status, DateTime.now().toUtc(),
                organizationId: org);
          final runtime = LicenseRuntimeService(
              databaseProvider: () async => db,
              activationStateRepository: repo);
          final decision = await runtime.refreshFromStoredLicense();
          for (final role in RoleKeys.canonical) {
            final users = UserService(databaseProvider: () async => db);
            expect(await users.authenticateUser(role, 'wrong'), isNull);
            final user =
                (await users.authenticateUser(role, 'Local-Password123!'))!;
            expect(user.role, role);
            expect(user.identityAccountId, isNotNull);
            final person = user.identityAccountId;
            var session = AuthSessionService(databaseProvider: () async => db);
            await session.saveLoginPreferences(
                username: role, rememberUsername: true, keepSignedIn: true);
            await session.createSession(user, keepSignedIn: true);
            await DeviceUnlockService().configure(
                userId: user.id, pin: '6372', enableBiometric: false);
            final secrets = await const FlutterSecureStorage().readAll();
            expect(secrets.values, isNot(contains('6372')));
            AuthSessionService.resetProcessMemoryForTesting();
            expect(AuthSessionService.authenticatedUserId, isNull);
            await db.close();
            db = await DatabaseMigration.initDatabase(pathOverride: path);
            session = AuthSessionService(databaseProvider: () async => db);
            final restored = (await session.restoreSession())!;
            expect(restored.identityAccountId, person);
            expect(restored.organizationId, org);
            expect(restored.role, role);
            final unlock = DeviceUnlockService();
            expect(await unlock.verifyPin(userId: restored.id, pin: '0000'),
                isFalse);
            expect(
                await unlock.verifyPin(
                    userId: 'other-workshop-user', pin: '6372'),
                isFalse);
            expect(await unlock.verifyPin(userId: restored.id, pin: '6372'),
                isTrue);
            expect(await unlock.authenticateBiometric(userId: restored.id),
                isFalse);
            final gate = CommercialAccessGateService(
                databaseProvider: () async => db,
                activationStateRepository: repo);
            final access = await gate.evaluate(restored);
            expect(access.allowed, isTrue, reason: access.code);
            expect(access.readOnly, !decision.isWritable);
            expect(
                (await gate.evaluate(
                        restored.copyWith(identityAccountId: 'another-person')))
                    .allowed,
                isFalse);
            expect(
                (await gate.evaluate(
                        restored.copyWith(organizationId: 'another-workshop')))
                    .allowed,
                isFalse);
            final permissions =
                PermissionService(databaseProvider: () async => db);
            expect(await permissions.canCurrent(PermissionKeys.backupRestore),
                role == 'owner');
            final grants = await db.query('auth_role_permissions',
                where: 'role_key = ?', whereArgs: [role]);
            expect(grants.map((r) => r['permission_key']).toSet(),
                AuthorizationPolicy.forRole(role));
            if (!decision.isWritable) {
              await expectLater(runtime.requireOperationalWrite(),
                  throwsA(isA<ReadOnlyOperationException>()));
              await expectLater(
                  db.insert('clients', {'name': 'blocked'}), throwsA(anything));
              await db.query('clients');
            }
            await session.logout();
            AuthSessionService.resetProcessMemoryForTesting();
            expect(await session.restoreSession(), isNull);
          }
          expect(await db.query('identity_accounts'), hasLength(5));
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          await db.close();
        }
      }, createHttpClient: (_) => throw StateError('Network unavailable'));
    });
  }
}
