import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_config.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_screen.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_identity_tables.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_secure_storage.dart';
import 'package:yalla_accounts/features/cloud_auth/supabase_identity_provider.dart';

class FakeIdentity implements CloudIdentityProvider {
  String issuer = 'https://project.supabase.co/auth/v1';
  String subject = 'remote-person';
  bool offline = false;
  int requests = 0;
  @override
  Future<VerifiedCloudIdentity> verifyIdentity() async {
    requests++;
    if (offline) throw StateError('Network unavailable');
    return VerifiedCloudIdentity(issuer, subject);
  }
}

class DiscardingSecureStorage extends FlutterSecureStorage {
  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  group('managed configuration and storage', () {
    const valid = CloudAuthConfig(
        url: 'https://project.supabase.co',
        publicKey: 'sb_publishable_fixture_public_only',
        releaseReady: true);
    test('disabled by default and rejects private keys or HTTP', () {
      expect(CloudAuthConfig.environment().enabled, isFalse);
      expect(valid.enabled, isTrue);
      expect(
          const CloudAuthConfig(
                  url: 'http://localhost',
                  publicKey: 'sb_publishable_fixture',
                  releaseReady: true)
              .enabled,
          isFalse);
      for (final secret in ['sb_secret_wrong', 'eyJservice_role', '']) {
        expect(
            CloudAuthConfig(
                    url: valid.url, publicKey: secret, releaseReady: true)
                .enabled,
            isFalse);
      }
    });
    test('PKCE callbacks require exact allowed scheme host path and code', () {
      expect(
          CloudAuthConfig.acceptsCallback(
              Uri.parse('${CloudAuthConfig.callback}?code=valid')),
          isTrue);
      expect(
          CloudAuthConfig.acceptsCallback(
              Uri.parse('${CloudAuthConfig.recovery}?code=valid')),
          isTrue);
      for (final value in [
        'https://evil/auth?code=valid',
        'yallaaccounts://evil/callback?code=valid',
        'yallaaccounts://auth/other?code=valid',
        '${CloudAuthConfig.callback}#access_token=bad',
        '${CloudAuthConfig.callback}?code=',
        'yallaaccounts://auth:55/callback?code=valid'
      ]) {
        expect(CloudAuthConfig.acceptsCallback(Uri.parse(value)), isFalse,
            reason: value);
      }
    });
    test(
        'session and PKCE use separate secure persisted keys and remove safely',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = CloudSecureStorage('fixture');
      final pkce = CloudPkceStorage(storage);
      await storage.persistSession('encrypted-by-platform');
      await pkce.setItem(key: 'verifier', value: 'private-verifier');
      expect(await CloudSecureStorage('fixture').accessToken(),
          'encrypted-by-platform');
      expect(await pkce.getItem(key: 'verifier'), 'private-verifier');
      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
      expect(await pkce.getItem(key: 'verifier'), 'private-verifier');
      await pkce.removeItem(key: 'verifier');
      expect(await pkce.getItem(key: 'verifier'), isNull);
    });
    test('silent storage write failure rejects session and PKCE', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage =
          CloudSecureStorage('discard', storage: DiscardingSecureStorage());
      await expectLater(storage.persistSession('secret'), throwsStateError);
      await expectLater(
          CloudPkceStorage(storage).setItem(key: 'verifier', value: 'secret'),
          throwsStateError);
    });
    testWidgets('commercial entry is hidden without configuration',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CloudAccountLinkTile()))));
      expect(find.text('ربط الحساب السحابي'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('local identity binding', () {
    late Database db;
    late FakeIdentity remote;
    late AppUser user;
    late CloudAuthService service;
    bool allowed = true;
    int sessions = 0;
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('CREATE TABLE identity_accounts (id TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE organizations (id TEXT PRIMARY KEY)');
      await db.execute(
          'CREATE TABLE organization_identity (singleton_id INTEGER PRIMARY KEY, organization_id TEXT)');
      await db.execute('''CREATE TABLE users (id TEXT PRIMARY KEY, name TEXT,
        role TEXT, status TEXT, organization_id TEXT, identity_account_id TEXT,
        created_at TEXT, email TEXT, must_change_password INTEGER DEFAULT 0)''');
      await db.insert('identity_accounts', {'id': 'person'});
      await db.insert('identity_accounts', {'id': 'person2'});
      await db.insert('organizations', {'id': 'workshop'});
      await db.insert('organizations', {'id': 'other-workshop'});
      await db.insert('organization_identity',
          {'singleton_id': 1, 'organization_id': 'workshop'});
      for (final id in ['user', 'other-user']) {
        await db.insert('users', {
          'id': id,
          'name': id,
          'role': 'owner',
          'status': 'active',
          'organization_id': 'workshop',
          'identity_account_id': id == 'user' ? 'person' : 'person2',
          'created_at': '2026-01-01',
          'email': 'same@example.com'
        });
      }
      await CloudIdentityTables.ensure(db);
      user = AppUser.fromMap(
          (await db.query('users', where: 'id = ?', whereArgs: ['user']))
              .single);
      remote = FakeIdentity();
      allowed = true;
      sessions = 0;
      service = CloudAuthService(
          identityProvider: remote,
          database: () async => db,
          authenticateLocal: (name, password) async =>
              password == 'valid-local-secret'
                  ? AppUser.fromMap((await db
                          .query('users', where: 'name = ?', whereArgs: [name]))
                      .single)
                  : null,
          accessAllowed: (_) async => allowed,
          createSession: (_) async {
            sessions++;
          });
    });
    tearDown(() async => db.close());
    test('email match alone never links or grants owner session', () async {
      await expectLater(
          service.enterLinkedWorkshop(), throwsA(isA<CloudAccountNotLinked>()));
      expect(sessions, 0);
      expect(await db.query('cloud_identity_links'), isEmpty);
    });
    test('wrong local password rejects link before cloud request', () async {
      await expectLater(service.link(user, 'wrong'), throwsStateError);
      expect(remote.requests, 0);
      expect(await db.query('cloud_identity_links'), isEmpty);
    });
    test('verified link is audited exactly once and survives reopen of service',
        () async {
      await service.link(user, 'valid-local-secret');
      await service.link(user, 'valid-local-secret');
      expect((await db.query('cloud_identity_links')).length, 1);
      expect(
          (await db.query('app_audit_events',
                  where: 'action = ?', whereArgs: ['CLOUD_IDENTITY_LINKED']))
              .length,
          1);
      final entered = await service.enterLinkedWorkshop();
      expect(entered.id, user.id);
      expect(entered.identityAccountId, 'person');
      expect(sessions, 1);
    });
    test('one cloud subject cannot be rebound to a different local person',
        () async {
      await service.link(user, 'valid-local-secret');
      final second = AppUser.fromMap(
          (await db.query('users', where: 'id = ?', whereArgs: ['other-user']))
              .single);
      await expectLater(
          service.link(second, 'valid-local-secret'), throwsStateError);
      expect(
          (await db.query('cloud_identity_links')).single['user_id'], 'user');
    });
    test('same subject from different issuer is not trusted', () async {
      await service.link(user, 'valid-local-secret');
      remote.issuer = 'https://another.supabase.co/auth/v1';
      await expectLater(
          service.enterLinkedWorkshop(), throwsA(isA<CloudAccountNotLinked>()));
      expect(sessions, 0);
    });
    test(
        'fresh network failure never creates local session from cached identity',
        () async {
      await service.link(user, 'valid-local-secret');
      remote.offline = true;
      await expectLater(service.enterLinkedWorkshop(), throwsStateError);
      expect(sessions, 0);
    });
    test('disabled user and changed workshop remain blocked', () async {
      await service.link(user, 'valid-local-secret');
      await db.update('users', {'status': 'inactive'},
          where: 'id = ?', whereArgs: ['user']);
      await expectLater(service.enterLinkedWorkshop(), throwsStateError);
      await db.update(
          'users', {'status': 'active', 'organization_id': 'other-workshop'},
          where: 'id = ?', whereArgs: ['user']);
      await expectLater(service.enterLinkedWorkshop(), throwsStateError);
      expect(sessions, 0);
    });
    test('canonical local role is reread; no remote owner role accepted',
        () async {
      await service.link(user, 'valid-local-secret');
      await db.update('users', {'role': 'viewer'},
          where: 'id = ?', whereArgs: ['user']);
      expect((await service.enterLinkedWorkshop()).role, 'viewer');
    });
    test('commercial denial blocks linked account', () async {
      await service.link(user, 'valid-local-secret');
      allowed = false;
      await expectLater(service.enterLinkedWorkshop(), throwsStateError);
      expect(sessions, 0);
    });
    test('mandatory local password change cannot be bypassed by cloud identity',
        () async {
      await service.link(user, 'valid-local-secret');
      await db.update('users', {'must_change_password': 1},
          where: 'id = ?', whereArgs: ['user']);
      await expectLater(service.enterLinkedWorkshop(), throwsStateError);
      expect(sessions, 0);
    });
    test('binding cannot be deleted or replaced silently', () async {
      await service.link(user, 'valid-local-secret');
      final row = (await db.query('cloud_identity_links')).single;
      await expectLater(
          db.delete('cloud_identity_links'), throwsA(isA<DatabaseException>()));
      await expectLater(
          db.insert('cloud_identity_links', row,
              conflictAlgorithm: ConflictAlgorithm.replace),
          throwsA(isA<DatabaseException>()));
      expect((await db.query('cloud_identity_links')).length, 1);
    });
    test('audit failure rolls back binding; user data preserved', () async {
      await db.execute('CREATE TABLE app_audit_events (id INTEGER)');
      await expectLater(service.link(user, 'valid-local-secret'),
          throwsA(isA<DatabaseException>()));
      expect(await db.query('cloud_identity_links'), isEmpty);
      expect((await db.query('users')).length, 2);
    });
  });
}
