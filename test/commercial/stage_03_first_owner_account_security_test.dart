import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/owner_bootstrap_tables.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
      (MethodCall call) async {
        switch (call.method) {
          case 'read':
            return null;
          case 'readAll':
            return <String, String>{};
          case 'containsKey':
            return false;
          case 'write':
          case 'delete':
          case 'deleteAll':
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  Future<String> currentOrganizationId(sq.Database db) async {
    final rows = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    expect(rows, hasLength(1));
    return rows.single['organization_id']!.toString();
  }

  Future<AppUser> seedClosedOwner(
    sq.Database db, {
    String userId = 'stage03-owner',
    String username = 'stage03-owner',
    String password = 'OwnerSecure123',
    String? recoveryCode,
    String? securityAnswer,
  }) async {
    final organizationId = await currentOrganizationId(db);
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('users', {
      'id': userId,
      'organization_id': organizationId,
      'name': username,
      'email': 'owner@example.local',
      'password': PasswordHasher.hash(password),
      'role': 'owner',
      'status': 'active',
      'created_at': now,
      'is_owner': 1,
      'must_change_password': 0,
      'failed_login_count': 0,
      'locked_until': null,
      'password_changed_at': now,
      if (recoveryCode != null)
        'recovery_code_hash': PasswordHasher.hash(recoveryCode),
      if (recoveryCode != null) 'recovery_code_used': 0,
      if (securityAnswer != null)
        'security_answer_hash': PasswordHasher.hash(securityAnswer),
    });

    await db.update(
      'owner_bootstrap_state',
      {
        'status': 'COMPLETED',
        'owner_user_id': userId,
        'completed_at': now,
        'updated_at': now,
      },
      where: 'singleton_id = 1',
    );

    await OwnerBootstrapTables.validate(db);

    return AppUser(
      id: userId,
      organizationId: organizationId,
      name: username,
      email: 'owner@example.local',
      role: 'owner',
      status: 'active',
      createdAt: DateTime.now(),
      isOwner: true,
    );
  }

  test('Stage 03 never auto-promotes a pre-bootstrap user to owner', () async {
    final temp =
        await Directory.systemTemp.createTemp('yalla_stage03_fail_closed_');
    final path = '${temp.path}${Platform.pathSeparator}stage03.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(databaseProvider: provider);

    try {
      final organizationId = await currentOrganizationId(db);
      final now = DateTime.now().toUtc().toIso8601String();

      await db.insert('users', {
        'id': 'unexpected-user',
        'organization_id': organizationId,
        'name': 'unexpected',
        'email': '',
        'password': PasswordHasher.hash('Unexpected123'),
        'role': 'cashier',
        'status': 'active',
        'created_at': now,
        'is_owner': 0,
        'must_change_password': 0,
      });

      await expectLater(
        users.authenticateUser('unexpected', 'Unexpected123'),
        throwsA(isA<StateError>()),
      );

      final row = (await db.query(
        'users',
        columns: ['is_owner', 'role'],
        where: 'id = ?',
        whereArgs: ['unexpected-user'],
      ))
          .single;

      expect(row['is_owner'], 0);
      expect(row['role'], 'cashier');

      await expectLater(
        OwnerBootstrapTables.validate(db),
        throwsA(isA<StateError>()),
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('Stage 03 authenticates only a canonically closed First Owner',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('yalla_stage03_owner_chain_');
    final path = '${temp.path}${Platform.pathSeparator}stage03.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(databaseProvider: provider);

    try {
      await seedClosedOwner(db);
      final authenticated =
          await users.authenticateUser('STAGE03-OWNER', 'OwnerSecure123');

      expect(authenticated, isNotNull);
      expect(authenticated!.isOwner, isTrue);
      expect(authenticated.role, 'owner');
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('Stage 03 requires owner password reauthentication for recovery changes',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_stage03_reauth_');
    final path = '${temp.path}${Platform.pathSeparator}stage03.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(databaseProvider: provider);
    final sessions = AuthSessionService(databaseProvider: provider);

    try {
      final owner = await seedClosedOwner(db);
      await sessions.createSession(owner);

      // Compatibility with pre-Stage-03 UI callers is compile-safe only.
      // Omitting the password must remain fail-closed and can never bypass
      // explicit owner reauthentication.
      await expectLater(
        users.generateOwnerRecoveryCode(),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        users.changeOwnerUsername('legacy-no-password'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        users.setSecurityQuestions(
          question1: 'Q1',
          question2: 'Q2',
          answer1: 'A1',
          answer2: 'A2',
        ),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        users.generateOwnerRecoveryCode(currentPassword: 'WrongPass123'),
        throwsA(isA<StateError>()),
      );

      final code = await users.generateOwnerRecoveryCode(
        currentPassword: 'OwnerSecure123',
      );
      expect(code, isNotNull);
      expect(code, startsWith('YA-'));

      final row = (await db.query(
        'users',
        columns: ['recovery_code_hash', 'recovery_code_used'],
        where: 'id = ?',
        whereArgs: [owner.id],
      ))
          .single;
      final stored = row['recovery_code_hash']?.toString() ?? '';

      expect(stored, isNot(code));
      expect(PasswordHasher.verify(code!, stored).isValid, isTrue);
      expect(row['recovery_code_used'], 0);

      await expectLater(
        users.changeOwnerUsername(
          'owner-renamed',
          currentPassword: 'WrongPass123',
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await users.changeOwnerUsername(
          'owner-renamed',
          currentPassword: 'OwnerSecure123',
        ),
        isTrue,
      );
    } finally {
      await sessions.logout();
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('Stage 03 keeps only the newest password-reset grant live', () async {
    final temp =
        await Directory.systemTemp.createTemp('yalla_stage03_reset_grant_');
    final path = '${temp.path}${Platform.pathSeparator}stage03.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    Future<sq.Database> provider() async => db;
    final users = UserService(databaseProvider: provider);

    try {
      await seedClosedOwner(
        db,
        securityAnswer: 'garage-answer|identity-answer',
      );

      final first = await users.createResetGrantWithSecurityAnswers(
        answer1: 'garage-answer',
        answer2: 'identity-answer',
      );
      final second = await users.createResetGrantWithSecurityAnswers(
        answer1: 'garage-answer',
        answer2: 'identity-answer',
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first, isNot(second));

      expect(
        await users.resetPasswordWithGrant(
          grantToken: first!,
          newPassword: 'ShouldNotWork123',
        ),
        isFalse,
        reason: 'A newer recovery grant must supersede every older grant.',
      );

      expect(
        await users.resetPasswordWithGrant(
          grantToken: second!,
          newPassword: 'NewestGrant123',
        ),
        isTrue,
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('Stage 03 account security UI asks for current owner password', () {
    final source = File(
      'lib/features/auth/screens/account_security_screen.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/auth/services/user_service.dart',
    ).readAsStringSync();

    expect(source, contains('إعادة التحقق من هوية المالك'));
    expect(source, contains('currentPassword: currentPassword'));
    expect(service, contains('_requireOwnerReauthentication'));
    expect(
        service, isNot(contains("'is_owner': 1,\n        'role': 'owner',")));
  });
}
