import 'dart:io';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/login_screen.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

class EmptyUsers extends UserService {
  @override
  Future<bool> hasAnyUsers() async => false;
}

class Picker extends FilePicker {
  int calls = 0;
  @override
  Future<FilePickerResult?> pickFiles(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      bool allowCompression = true,
      int compressionQuality = 30,
      bool allowMultiple = false,
      bool withData = false,
      bool withReadStream = false,
      bool lockParentWindow = false,
      bool readSequential = false}) async {
    calls++;
    return null;
  }
}

AppUser user(String role, {String id = 'test', bool flag = false}) => AppUser(
    id: id,
    name: 'owner',
    email: '',
    role: role,
    isOwner: flag,
    status: 'active',
    createdAt: DateTime(2026));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthSessionService session;
  late Picker picker;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    session = AuthSessionService();
    picker = Picker();
    FilePicker.platform = picker;
    AuthorizationGuard.disableInteractiveEnforcement();
  });
  tearDown(() async {
    await session.endEphemeralPreviewSession();
    AuthorizationGuard.disableInteractiveEnforcement();
  });

  for (final role in ['owner', 'Owner', 'OWNER', ' owner ']) {
    test('$role canonical owner still needs a licensed restore session',
        () async {
      final actor =
          await session.startPreviewSession(user(role), localUser: false);
      expect(actor.role, RoleKeys.owner);
      expect(actor.isOwner, isTrue);
      expect(AppUser.fromMap(actor.toMap()).role, RoleKeys.owner);
      expect(await PermissionService().canCurrent(PermissionKeys.backupRestore),
          isTrue);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final temp = await Directory.systemTemp.createTemp('restore_license_');
      final db = await DatabaseMigration.initDatabase(
          pathOverride: '${temp.path}/test.db');
      DatabaseMigration.useDatabaseForTesting(db);
      try {
        await expectLater(BackupService.pickEncryptedBackup(),
            throwsA(isA<ReadOnlyOperationException>()));
        expect(picker.calls, 0);
      } finally {
        DatabaseMigration.useDatabaseForTesting(null);
        await db.close();
      }
    });
  }
  for (final role in [
    ...RoleKeys.all.where((r) => r != RoleKeys.owner),
    'UNKNOWN'
  ]) {
    test('$role denied despite owner username and stale owner flag', () async {
      await session.startPreviewSession(user(role.toUpperCase(), flag: true),
          localUser: false);
      expect(await PermissionService().canCurrent(PermissionKeys.backupRestore),
          isFalse);
      await expectLater(BackupService.pickEncryptedBackup(), throwsStateError);
      await expectLater(
          BackupService.restoreEncryptedFromPath('missing', password: 'x'),
          throwsStateError);
      expect(picker.calls, 0);
    });
  }
  test('logout removes preview authority', () async {
    await session.startPreviewSession(user('owner'), localUser: false);
    await session.logout();
    expect(await PermissionService().canCurrent(PermissionKeys.backupRestore),
        isFalse);
    await expectLater(BackupService.pickEncryptedBackup(), throwsStateError);
  });
  test('existing local user role is re-read without modifying persisted data',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE users(id TEXT, name TEXT, role TEXT, status TEXT, is_owner INTEGER)');
    await db.insert('users', {
      'id': 'local',
      'name': 'real owner',
      'role': 'OWNER',
      'status': 'active',
      'is_owner': 0
    });
    session = AuthSessionService(databaseProvider: () async => db);
    final permissions = PermissionService(databaseProvider: () async => db);
    final before = await db.query('users');
    await session.startPreviewSession(user('owner', id: 'local'),
        localUser: true);
    expect(await permissions.canCurrent(PermissionKeys.backupRestore), isTrue);
    expect(await db.query('users'), before);
    await db.update('users', {'role': 'Manager'});
    expect(await permissions.canCurrent(PermissionKeys.backupRestore), isFalse);
    await db.delete('users');
    expect(await permissions.canCurrent(PermissionKeys.backupRestore), isFalse);
    await session.endEphemeralPreviewSession();
    await db.close();
  });
  test(
      'token session uses persisted role, never cached role or legacy preferences',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE users(id TEXT, name TEXT, role TEXT, status TEXT)');
    await db.execute(
        'CREATE TABLE auth_sessions(id TEXT, user_id TEXT, token_hash TEXT, created_at TEXT, expires_at TEXT, last_seen_at TEXT, revoked_at TEXT)');
    await db.insert('users', {
      'id': 'persisted',
      'name': 'owner',
      'role': 'Owner',
      'status': 'active'
    });
    session = AuthSessionService(databaseProvider: () async => db);
    final permissions = PermissionService(databaseProvider: () async => db);
    await session.saveLoginPreferences(
        username: 'owner', rememberUsername: true, keepSignedIn: true);
    await session.createSession(user('owner', id: 'persisted'),
        keepSignedIn: true);
    expect((await session.restoreSession())?.role, RoleKeys.owner);
    expect(await permissions.canCurrent(PermissionKeys.backupRestore), isTrue);
    await db.update('users', {'role': 'ACCOUNTANT'});
    expect(await permissions.canCurrent(PermissionKeys.backupRestore), isFalse);
    expect(
        await permissions.hasPermissionForUser(
            'persisted', PermissionKeys.backupRestore),
        isFalse);
    await session.logout();
    expect(await permissions.canCurrent(PermissionKeys.backupRestore), isFalse);
    await db.close();
  });
  testWidgets(
      'owner username alone never grants a session or restore permission',
      (tester) async {
    final container = ProviderContainer(
        overrides: [userServiceProvider.overrideWithValue(EmptyUsers())]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: const LoginScreen(),
            onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('signed in'))))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'OWNER');
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();
    expect(find.text('signed in'), findsNothing);
    expect(container.read(currentUserProvider), isNull);
    expect(picker.calls, 0);
  });
}
