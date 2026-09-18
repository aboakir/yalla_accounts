import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('P1.002 password hashes are salted and legacy SHA-256 is upgradeable',
      () {
    const password = 'StrongPass123';
    final a = PasswordHasher.hash(password);
    final b = PasswordHasher.hash(password);

    expect(a, isNot(b));
    expect(a.startsWith('${PasswordHasher.scheme}\$'), isTrue);
    expect(PasswordHasher.iterations, greaterThanOrEqualTo(100000));
    expect(PasswordHasher.verify(password, a).isValid, isTrue);

    final legacy = PasswordHasher.legacySha256ForTest(password);
    final legacyCheck = PasswordHasher.verify(password, legacy);
    expect(legacyCheck.isValid, isTrue);
    expect(legacyCheck.needsUpgrade, isTrue);
  });

  test('P1.002 fresh install has no seeded universal user or activation batch',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_p1_002_fresh_');
    final path = '${temp.path}${Platform.pathSeparator}fresh.db';

    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      final version = sq.Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      expect(version, DatabaseConstants.dbVersion);

      final users = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM users'),
          ) ??
          -1;
      expect(users, 0);

      final activationCodes = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM activation_codes'),
          ) ??
          -1;
      expect(activationCodes, 0);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();

      expect(names.contains('auth_sessions'), isTrue);
      expect(names.contains('password_reset_grants'), isTrue);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.002 first owner is explicit and a second registration is blocked',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_p1_002_owner_');
    final path = '${temp.path}${Platform.pathSeparator}owner.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(
        databaseProvider: provider, enforceActivationForFirstOwner: false);

    try {
      const password = 'OwnerSecure123';
      final ok = await users.registerUser(
        AppUser(
          id: 'ignored',
          name: 'owner',
          email: 'owner@example.local',
          role: 'owner',
          status: 'active',
          createdAt: DateTime.now(),
          isOwner: true,
        ),
        password,
      );

      expect(ok, isTrue);

      final row = (await db.query('users')).single;
      expect(row['is_owner'], 1);
      expect(row['role'], 'owner');
      expect(row['password'].toString().startsWith('pbkdf2_sha256\$'), isTrue);

      final authenticated = await users.authenticateUser('OWNER', password);
      expect(authenticated, isNotNull);

      await expectLater(
        users.registerUser(
          AppUser(
            id: 'ignored-2',
            name: 'second',
            email: '',
            role: 'user',
            status: 'active',
            createdAt: DateTime.now(),
          ),
          'AnotherSecure123',
        ),
        throwsA(isA<StateError>()),
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.002 legacy login preserves access and upgrades the password hash',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_p1_002_legacy_');
    final path = '${temp.path}${Platform.pathSeparator}legacy.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(
        databaseProvider: provider, enforceActivationForFirstOwner: false);

    try {
      const password = 'LegacyPass123';
      await db.insert('users', {
        'id': 'legacy-owner',
        'name': 'legacy',
        'email': '',
        'password': PasswordHasher.legacySha256ForTest(password),
        'role': 'owner',
        'status': 'active',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_owner': 1,
        'must_change_password': 1,
      });

      final authenticated = await users.authenticateUser('legacy', password);
      expect(authenticated, isNotNull);
      expect(authenticated!.mustChangePassword, isTrue);

      final row = (await db.query(
        'users',
        where: 'id = ?',
        whereArgs: ['legacy-owner'],
      ))
          .single;

      expect(row['password'].toString().startsWith('pbkdf2_sha256\$'), isTrue);
      expect(row['must_change_password'], 1);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.002 session is token-backed and logout revokes it', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_p1_002_session_');
    final path = '${temp.path}${Platform.pathSeparator}session.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(
        databaseProvider: provider, enforceActivationForFirstOwner: false);
    final sessions = AuthSessionService(databaseProvider: provider);

    try {
      const password = 'SessionSecure123';
      await users.registerUser(
        AppUser(
          id: 'ignored',
          name: 'session-owner',
          email: '',
          role: 'owner',
          status: 'active',
          createdAt: DateTime.now(),
          isOwner: true,
        ),
        password,
      );

      final owner = await users.authenticateUser(
        'session-owner',
        password,
      );
      expect(owner, isNotNull);

      await sessions.createSession(owner!);
      expect(await sessions.restoreSession(), isNotNull);

      final activeSessions = sq.Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM auth_sessions WHERE revoked_at IS NULL',
            ),
          ) ??
          0;
      expect(activeSessions, 1);

      await sessions.logout();
      expect(await sessions.restoreSession(), isNull);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.002 five failed logins trigger a local lockout', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_p1_002_lockout_');
    final path = '${temp.path}${Platform.pathSeparator}lockout.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(
        databaseProvider: provider, enforceActivationForFirstOwner: false);

    try {
      await db.insert('users', {
        'id': 'lockout-owner',
        'name': 'lockout',
        'email': '',
        'password': PasswordHasher.legacySha256ForTest('CorrectPass123'),
        'role': 'owner',
        'status': 'active',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_owner': 1,
        'must_change_password': 1,
      });

      for (var i = 0; i < 5; i++) {
        expect(
          await users.authenticateUser('lockout', 'WrongPass999'),
          isNull,
        );
      }

      final row = (await db.query(
        'users',
        columns: ['failed_login_count', 'locked_until'],
        where: 'id = ?',
        whereArgs: ['lockout-owner'],
      ))
          .single;

      expect(row['failed_login_count'], 5);
      final lockedUntil =
          DateTime.tryParse(row['locked_until']?.toString() ?? '');
      expect(lockedUntil, isNotNull);
      expect(lockedUntil!.isAfter(DateTime.now().toUtc()), isTrue);

      expect(
        await users.authenticateUser('lockout', 'CorrectPass123'),
        isNull,
        reason: 'Correct credentials must not bypass an active lockout.',
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.002 recovery grant is one-time and revokes active sessions',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('yalla_p1_002_recovery_');
    final path = '${temp.path}${Platform.pathSeparator}recovery.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(
        databaseProvider: provider, enforceActivationForFirstOwner: false);
    final sessions = AuthSessionService(databaseProvider: provider);

    try {
      const replacement = 'RecoveryNew456';
      const userId = 'recovery-owner-id';

      await db.insert('users', {
        'id': userId,
        'name': 'recovery-owner',
        'email': '',
        'password': PasswordHasher.legacySha256ForTest('RecoveryOld123'),
        'role': 'owner',
        'status': 'active',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_owner': 1,
        'must_change_password': 1,
        'security_answer_hash': PasswordHasher.legacySha256ForTest(
          'garage-answer|identity-answer',
        ),
      });

      final owner = AppUser(
        id: userId,
        name: 'recovery-owner',
        email: '',
        role: 'owner',
        status: 'active',
        createdAt: DateTime.now(),
        isOwner: true,
        mustChangePassword: true,
      );
      await sessions.createSession(owner);

      final grant = await users.createResetGrantWithSecurityAnswers(
        answer1: 'garage-answer',
        answer2: 'identity-answer',
      );
      expect(grant, isNotNull);
      final grantToken = grant!;

      expect(
        await users.resetPasswordWithGrant(
          grantToken: grantToken,
          newPassword: replacement,
        ),
        isTrue,
      );

      expect(await sessions.restoreSession(), isNull);

      expect(
        await users.resetPasswordWithGrant(
          grantToken: grantToken,
          newPassword: 'AnotherPass789',
        ),
        isFalse,
        reason: 'A password-reset grant must be single use.',
      );

      final row = (await db.query(
        'users',
        columns: ['password', 'must_change_password'],
        where: 'id = ?',
        whereArgs: [userId],
      ))
          .single;

      expect(
        PasswordHasher.verify(
          replacement,
          row['password']?.toString() ?? '',
        ).isValid,
        isTrue,
      );
      expect(row['must_change_password'], 0);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.002 route source no longer maps login/register/logout to dashboard',
      () {
    final routes = source('lib/core/routes/app_routes.dart');
    final startup = source('lib/features/startup/startup_screen.dart');

    expect(routes.contains('const LoginScreen()'), isTrue);
    expect(routes.contains('const WorkshopOnboardingScreen()'), isTrue);
    expect(routes.contains('const ForgotAccessScreen()'), isTrue);
    expect(routes.contains('const LogoutScreen()'), isTrue);
    expect(routes.contains('AuthenticatedRouteGate'), isTrue);
    expect(
      routes.contains(
        'name == login ||\n        name == forgotAccess ||\n        name == register',
      ),
      isFalse,
    );

    expect(startup.contains('currentUserProvider.notifier'), isTrue);
    expect(
        source('lib/features/auth/screens/login_screen.dart')
            .contains('restoreSession()'),
        isTrue);
    expect(startup.contains('AppRoutes.login'), isTrue);
    expect(
      startup.contains(
        'Navigator.of(context).pushReplacementNamed(\n      AppRoutes.dashboard',
      ),
      isFalse,
    );
  });

  test('P1.002 legacy default-admin/offline signing paths are disabled', () {
    final seeder = source(
      'lib/core/services/db/seeders/user_seeder.dart',
    );
    final admin = source(
      'lib/features/auth/services/admin_setup.dart',
    );
    final activation = source(
      'lib/features/auth/services/activation_code_validator.dart',
    );

    expect(seeder.contains('defaultPassword'), isFalse);
    expect(seeder.contains('batch.insert'), isFalse);
    expect(admin.contains('openDatabase('), isFalse);
    expect(admin.contains('getDatabasesPath('), isFalse);
    expect(activation.contains('YALLA-ACTIVATION-SECRET'), isFalse);
    expect(
      activation.contains('Legacy client-side activation signing is disabled'),
      isTrue,
    );
  });
}
