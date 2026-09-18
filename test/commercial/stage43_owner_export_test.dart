import 'package:yalla_accounts/core/services/db/tables/owner_bootstrap_tables.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/auth/services/owner_data_export_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

class Credentials extends UserService {
  Credentials(this.user);
  final AppUser user;
  @override
  Future<AppUser?> authenticateUser(String name, String password) async =>
      password == 'correct' ? user : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late Directory dir;
  late AuthSessionService session;
  late AppUser owner;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('owner_export_');
    db = await DatabaseMigration.initDatabase(
        pathOverride: "${dir.path}/test.db");
    session = AuthSessionService(databaseProvider: () async => db);
    owner = AppUser(
        id: 'export-owner',
        name: 'owner',
        email: '',
        role: 'Owner',
        status: 'active',
        createdAt: DateTime(2026));
    await db.insert('users', {...owner.toMap(), 'password': 'fixture-only'});
    await OwnerBootstrapTables.ensure(db);
  });
  tearDown(() async {
    await session.logout();
    await db.close();
  });
  test('restore revokes every imported session and removes device unlock',
      () async {
    await session.createSession(owner, keepSignedIn: true);
    await session.invalidateAfterRestore();
    expect(await session.restoreSession(), isNull);
    expect(
        await db.query('auth_sessions', where: 'revoked_at IS NULL'), isEmpty);
    expect(AuthSessionService.authenticatedUserId, isNull);
  });
  test('v70 readonly upgrade retains business data and financial guards',
      () async {
    await db.insert('clients', {'name': 'preserved', 'type': 'individual'});
    await db.update('license_runtime_state', {'mode': 'READ_ONLY_EXPIRED'});
    await db.execute(
        "CREATE TRIGGER yalla_sec011_ro_backup_runs_insert BEFORE INSERT ON backup_runs BEGIN SELECT RAISE(ABORT, 'legacy backup guard'); END");
    await db.setVersion(70);
    await db.close();
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    expect(await db.getVersion(), DatabaseConstants.dbVersion);
    expect((await db.query('clients')).single['name'], 'preserved');
    expect(
        await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE name='yalla_sec011_ro_backup_runs_insert'"),
        isEmpty);
    await expectLater(
        db.insert('clients', {'name': 'blocked', 'type': 'individual'}),
        throwsA(anything));
  });
  test('recovery permits only create/export and never financial attribution',
      () async {
    await session.createRecoverySession(owner);
    final permissions = PermissionService(databaseProvider: () async => db);
    for (final permission in PermissionKeys.all) {
      expect(
          await permissions.canCurrent(permission),
          [PermissionKeys.backupCreate, PermissionKeys.backupExport]
              .contains(permission),
          reason: permission);
    }
    CurrentUserContext.bindActiveUserReader(() => owner.id);
    expect(await CurrentUserContext.userId(), isNull);
    CurrentUserContext.bindActiveUserReader(() => null);
    await session.logout();
    expect(AuthSessionService.isRecoverySession, isFalse);
    expect(await session.restoreSession(), isNull);
  });
  for (final role in RoleKeys.all) {
    test('export credentials with role $role', () async {
      final user = AppUser(
          id: role == RoleKeys.owner ? owner.id : 'other',
          name: role == RoleKeys.owner ? 'owner' : 'other',
          email: '',
          role: role,
          status: 'active',
          createdAt: DateTime(2026));
      if (role != RoleKeys.owner) {
        await db.insert('users', {...user.toMap(), 'password': 'fixture-only'});
      }
      var copied = false;
      final service = OwnerDataExportService(
          users: Credentials(user),
          sessions: session,
          create: (_) async {
            copied = true;
            expect(AuthSessionService.isRecoverySession, isTrue);
            return EncryptedBackupResult(
                path: 'fixture',
                sizeBytes: 1,
                sha256Hex: '',
                createdAt: DateTime(2026),
                kind: 'owner_recovery',
                fileCount: 1);
          },
          share: (_) async {});
      final action = service.export(
          username: 'owner',
          password: 'correct',
          backupPassword: 'long-password');
      if (role == RoleKeys.owner) {
        expect(await action, isTrue);
      } else {
        await expectLater(action, throwsStateError);
      }
      expect(copied, role == RoleKeys.owner);
      expect(await session.restoreSession(), isNull);
    });
  }
  test('wrong credentials and failed backup leave no authority', () async {
    final service = OwnerDataExportService(
        users: Credentials(owner),
        sessions: session,
        create: (_) async => throw StateError('disk full'));
    await expectLater(
        service.export(
            username: 'owner',
            password: 'wrong',
            backupPassword: 'long-password'),
        throwsStateError);
    expect(await session.restoreSession(), isNull);
    await expectLater(
        service.export(
            username: 'owner',
            password: 'correct',
            backupPassword: 'long-password'),
        throwsStateError);
    expect(await session.restoreSession(), isNull);
    expect(AuthSessionService.isRecoverySession, isFalse);
  });
  test(
      'expired license permits backup audit but still denies business writes and audit tampering',
      () async {
    await db.update('license_runtime_state', {'mode': 'READ_ONLY_EXPIRED'});
    await db.update('backup_guardian_settings', {'weekly_enabled': 1});
    await db.insert('app_audit_events', {
      'created_at': '2026-09-09',
      'action': 'BACKUP_CREATED',
      'entity_type': 'BACKUP'
    });
    await expectLater(
        db.insert('clients', {'name': 'blocked', 'type': 'individual'}),
        throwsA(anything));
    await expectLater(db.delete('app_audit_events'), throwsA(anything));
    await expectLater(db.update('app_audit_events', {'action': 'tampered'}),
        throwsA(anything));
  });
}
