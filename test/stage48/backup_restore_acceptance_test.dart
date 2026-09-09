import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/device_identity/device_fingerprint_service.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/yalla_backup_codec.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

const testPin =
    '21fe31dfa154a261626bf854046fd2271b7bed4b6abe45aa58877ef47f9721b9';
const password = 'Stage48-test-only-password';

class Fingerprint implements DeviceFingerprintProvider {
  @override
  Future<DeviceFingerprintSnapshot> collect() async =>
      const DeviceFingerprintSnapshot(
          sha256Hex:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          platform: 'test',
          appVersion: '1.0');
}

String canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(canonical).join(',')}]';
  return jsonEncode(value);
}

String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Future<void> license(Database db, {bool expired = false}) async {
  final identity =
      await DeviceIdentityService(fingerprintProvider: Fingerprint())
          .ensureCurrent();
  final now = DateTime.now().toUtc();
  final expiry = now.add(Duration(days: expired ? -1 : 30));
  final payload = <String, Object?>{
    'schema_version': 1,
    'issuer': 'yalla-licensing',
    'license_id': 'stage48-license',
    'subscription_id': 'stage48-subscription',
    'organization_id': identity.organizationId,
    'installation_id': identity.installationId,
    'device_id': identity.deviceId,
    'device_public_key_sha256': identity.publicKeySha256,
    'issued_at': now.subtract(const Duration(days: 2)).toIso8601String(),
    'not_before': now.subtract(const Duration(days: 2)).toIso8601String(),
    'expires_at': expiry.toIso8601String(),
    'entitlement_revision': 1,
    'entitlements': {'ACCOUNTING_CORE': true, 'MAX_USERS': 5, 'MAX_DEVICES': 2},
  };
  const seed =
      '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
  final key = await Ed25519().newKeyPairFromSeed([
    for (var i = 0; i < seed.length; i += 2)
      int.parse(seed.substring(i, i + 2), radix: 16)
  ]);
  final pub = await key.extractPublicKey();
  expect(sha256.convert(pub.bytes).toString(), testPin);
  final bytes = utf8.encode(canonical(payload));
  final signature = await Ed25519().sign(bytes, keyPair: key);
  final envelope = {
    'typ': 'YALLA-LICENSE',
    'alg': 'EdDSA',
    'kid': 'stage48-test',
    'payload': payload,
    'payload_sha256': sha256.convert(bytes).toString(),
    'signature': b64(signature.bytes)
  };
  final keyset = {
    'issuer': 'yalla-licensing',
    'keys': [
      {
        'kid': 'stage48-test',
        'alg': 'EdDSA',
        'status': 'ACTIVE',
        'public_key': b64(pub.bytes),
        'public_key_sha256': testPin,
        'not_before': now.subtract(const Duration(days: 3)).toIso8601String()
      }
    ]
  };
  await db.insert(
      'license_activation_state',
      {
        'singleton_id': 1,
        'organization_id': identity.organizationId,
        'installation_id': identity.installationId,
        'device_id': identity.deviceId,
        'status': 'ACTIVE',
        'activation_id': 'stage48-activation',
        'license_id': 'stage48-license',
        'subscription_id': 'stage48-subscription',
        'license_expires_at': expiry.toIso8601String(),
        'entitlement_revision': 1,
        'signed_license_envelope_json': jsonEncode(envelope),
        'verification_keyset_json': jsonEncode(keyset),
        'activated_at': now.toIso8601String(),
        'last_online_validation_at': now.toIso8601String(),
        'updated_at': now.toIso8601String()
      },
      conflictAlgorithm: ConflictAlgorithm.replace);
}

void main() {
  // Protect against any indirect canonical DB lookup during a failing reopen.
  // The command must opt in to a throwaway fallback database directory.
  final fallback = Platform.environment['YALLA_ACCOUNTS_DB_DIR'] ?? '';
  if (!p.basename(fallback).startsWith('stage48_isolated_')) {
    test('Stage48 database acceptance requires isolated process directory',
        () {},
        skip:
            'Set YALLA_ACCOUNTS_DB_DIR to a temporary stage48_isolated_* directory');
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temp;
  late Directory root;
  late Database db;
  late String livePath;
  var session = AuthSessionService();
  bool failInstalledOpen = false;
  Future<void> reopen() async {
    if (failInstalledOpen &&
        await Directory('$livePath.restore-journal').exists()) {
      failInstalledOpen = false;
      throw StateError('stage48 injected post-replacement open failure');
    }
    db = await DatabaseMigration.initDatabase(pathOverride: livePath);
    DatabaseMigration.useDatabaseForTesting(db);
  }

  Future<void> signIn() async {
    final actor = AppUser.fromMap(
        (await db.query('users', where: 'id=?', whereArgs: ['owner'])).single);
    session = AuthSessionService();
    await session.createSession(actor);
    AuthorizationGuard.enableInteractiveEnforcement();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('yalla_stage48_');
    root = await Directory(p.join(temp.path, 'YallaAccounts')).create();
    // Every path used by production backup code is inside this fixture.
    YallaStorageService.useRootDirectoryForTesting(root);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => temp.path);
    livePath = p.join(root.path, DatabaseConstants.dbName);
    await reopen();
    BackupService.configureTestDatabase(
        path: () async => livePath,
        close: (checkpoint) async {
          await DatabaseMigration.closeDatabase(checkpoint: checkpoint);
          DatabaseMigration.useDatabaseForTesting(db);
        },
        reopen: reopen);
    await WorkshopSettingsService.createTable(db);
    await db.insert('users', {
      'id': 'owner',
      'name': 'Owner',
      'password': 'test-only',
      'role': 'owner',
      'is_owner': 1,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String()
    });
    await db.update('owner_bootstrap_state', {
      'status': 'COMPLETED',
      'owner_user_id': 'owner',
      'completed_at': DateTime.now().toUtc().toIso8601String()
    });
    await db
        .insert('clients', {'name': 'Preserved client', 'type': 'individual'});
    await db.insert('repairs', {
      'id': 'repair48',
      'beneficiaryName': 'Preserved client',
      'imagePaths': jsonEncode(['repairs/photo48.png'])
    });
    await db.insert(
        'workshop_settings',
        {
          'id': 1,
          'workshopName': 'Stage48 Workshop',
          'logoPath': 'documents/branding/logo48.png'
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('app_audit_events', {
      'created_at': DateTime.now().toIso8601String(),
      'action': 'STAGE48_FIXTURE',
      'entity_type': 'WORKSHOP'
    });
    // Unknown future change tables must survive a whole-database backup too.
    await db.execute(
        'CREATE TABLE stage48_change_fixture(id TEXT PRIMARY KEY, value TEXT)');
    await db.insert('stage48_change_fixture',
        {'id': 'change48', 'value': 'preserved change'});
    for (final rel in [
      'repairs/photo48.png',
      'documents/branding/logo48.png'
    ]) {
      final file = File(p.join(root.path, rel));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRz8AAAAASUVORK5CYII='));
    }
    await signIn();
  });
  tearDown(() async {
    AuthorizationGuard.disableInteractiveEnforcement();
    await session.logout();
    await DatabaseMigration.closeDatabase();
    DatabaseMigration.useDatabaseForTesting(null);
    BackupService.configureTestDatabase();
    YallaStorageService.useRootDirectoryForTesting(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await temp.delete(recursive: true);
    failInstalledOpen = false;
  });

  test(
      'nonempty encrypted backup includes all database tables, media and checksums',
      () async {
    final backup =
        await BackupService.createEncryptedBackup(password: password);
    expect(p.basename(backup.path),
        BackupService.backupFileName(backup.createdAt));
    expect(backup.fileCount, 3);
    expect(backup.sizeBytes, greaterThan(0));
    final manifest = await BackupService.validateEncryptedBackup(backup.path,
        password: password);
    expect(manifest.dbVersion, DatabaseConstants.dbVersion);
    expect(
        manifest.files.map((e) => e['path']),
        containsAll([
          'database/${DatabaseConstants.dbName}',
          'storage/repairs/photo48.png',
          'storage/documents/branding/logo48.png'
        ]));
    final zip = File(p.join(temp.path, 'inspect.zip'));
    await YallaBackupCodec.decryptFile(
        input: File(backup.path), output: zip, password: password);
    final unpack = p.join(temp.path, 'inspect');
    await extractFileToDisk(zip.path, unpack);
    final snapshot = await databaseFactoryFfi.openDatabase(
        p.join(unpack, 'database', DatabaseConstants.dbName),
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    try {
      expect(
          (await snapshot.query('clients')).single['name'], 'Preserved client');
      expect((await snapshot.query('workshop_settings')).single['workshopName'],
          'Stage48 Workshop');
      expect((await snapshot.query('stage48_change_fixture')).single['value'],
          'preserved change');
      expect(
          await snapshot.query('app_audit_events',
              where: 'action=?', whereArgs: ['STAGE48_FIXTURE']),
          hasLength(1));
    } finally {
      await snapshot.close();
    }
    final again = await BackupService.createEncryptedBackup(password: password);
    expect(again.path, isNot(backup.path));
    expect(await File(backup.path).exists(), isTrue);
    expect((await BackupService.latestEncryptedBackup())!.path, again.path);
    final legacy = await File(backup.path)
        .copy(p.join(root.path, 'backups', 'legacy.yallabackup'));
    expect(
        await BackupService.validateEncryptedBackup(legacy.path,
            password: password),
        isA<BackupManifest>());
  });

  test(
      'ciphertext corruption is rejected and current database/media stay unchanged',
      () async {
    final backup =
        await BackupService.createEncryptedBackup(password: password);
    final bytes = await File(backup.path).readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    final corrupt =
        await File(p.join(temp.path, 'corrupt.yab')).writeAsBytes(bytes);
    await expectLater(
        BackupService.validateEncryptedBackup(corrupt.path, password: password),
        throwsStateError);
    expect((await db.query('clients')).single['name'], 'Preserved client');
    expect(await File(p.join(root.path, 'repairs/photo48.png')).length(),
        greaterThan(0));
  });

  test('valid encryption cannot hide a bad checksum or unlisted archive file',
      () async {
    final backup =
        await BackupService.createEncryptedBackup(password: password);
    final zip = File(p.join(temp.path, 'modify.zip'));
    await YallaBackupCodec.decryptFile(
        input: File(backup.path), output: zip, password: password);
    final unpack = Directory(p.join(temp.path, 'modify'));
    await extractFileToDisk(zip.path, unpack.path);
    final manifestFile = File(p.join(unpack.path, 'manifest.json'));
    final originalManifest = await manifestFile.readAsString();
    Future<File> repack(String name) async {
      final editedZip = p.join(temp.path, '$name.zip');
      final encoder = ZipFileEncoder()..create(editedZip);
      try {
        await for (final entry in unpack.list(recursive: true)) {
          if (entry is File) {
            await encoder.addFile(
                entry,
                p
                    .relative(entry.path, from: unpack.path)
                    .replaceAll('\\', '/'));
          }
        }
      } finally {
        await encoder.close();
      }
      final out = File(p.join(temp.path, '$name.yab'));
      await YallaBackupCodec.encryptFile(
          input: File(editedZip), output: out, password: password);
      return out;
    }

    final manifest = jsonDecode(originalManifest) as Map<String, dynamic>;
    (manifest['files'] as List).first['sha256'] = List.filled(64, '0').join();
    await manifestFile.writeAsString(jsonEncode(manifest));
    final badHash = await repack('bad_hash');
    await expectLater(
        BackupService.validateEncryptedBackup(badHash.path, password: password),
        throwsStateError);
    await manifestFile.writeAsString(originalManifest);
    await File(p.join(unpack.path, 'storage', 'unlisted.txt'))
        .writeAsString('not declared');
    final unlisted = await repack('unlisted');
    await expectLater(
        BackupService.validateEncryptedBackup(unlisted.path,
            password: password),
        throwsStateError);
  });

  test(
      'failed backup reopen never opens canonical fallback for failure logging',
      () async {
    final fallbackDb = File(p.join(fallback, DatabaseConstants.dbName));
    expect(await fallbackDb.exists(), isFalse);
    BackupService.configureTestDatabase(
      path: () async => livePath,
      close: (checkpoint) =>
          DatabaseMigration.closeDatabase(checkpoint: checkpoint),
      reopen: () async {
        throw StateError('injected snapshot reopen failure');
      },
    );
    await expectLater(BackupService.createEncryptedBackup(password: password),
        throwsStateError);
    expect(await fallbackDb.exists(), isFalse);
    await reopen();
    expect((await db.query('clients')).single['name'], 'Preserved client');
    expect(await db.query('backup_runs'), isEmpty);
  });

  const hasPin =
      String.fromEnvironment('YALLA_LICENSE_TRUSTED_KEY_SHA256') == testPin;
  final skip = hasPin
      ? false
      : 'Run with the documented Stage48 test-only license trust pin';
  test(
      'licensed Owner restore replaces data/media, logs restoration and invalidates session',
      () async {
    await license(db);
    await LicenseRuntimeService().requireOperationalWrite();
    final backup =
        await BackupService.createEncryptedBackup(password: password);
    final image = File(p.join(root.path, 'repairs/photo48.png'));
    final original = await image.readAsBytes();
    await db.update('clients', {'name': 'After backup'});
    await db.update('workshop_settings', {'workshopName': 'Changed workshop'});
    await image.writeAsString('Changed image');
    final legacy =
        await File(backup.path).copy(p.join(temp.path, 'legacy.yallabackup'));
    await BackupService.restoreEncryptedFromPath(legacy.path,
        password: password);
    expect((await db.query('clients')).single['name'], 'Preserved client');
    expect((await db.query('workshop_settings')).single['workshopName'],
        'Stage48 Workshop');
    expect((await db.query('stage48_change_fixture')).single['value'],
        'preserved change');
    expect(await image.readAsBytes(), original);
    expect(await BackupService.lastRestoreAt(), isNotNull);
    expect(await AuthSessionService().restoreSession(), isNull);
    expect(
        await db.query('auth_sessions', where: 'revoked_at IS NULL'), isEmpty);
    expect(await Directory('$livePath.restore-journal').exists(), isFalse);
  }, skip: skip);

  test(
      'failure after database and image replacement rolls back both and keeps login',
      () async {
    await license(db);
    await LicenseRuntimeService().requireOperationalWrite();
    final backup =
        await BackupService.createEncryptedBackup(password: password);
    await db.update('clients', {'name': 'Must survive failed restore'});
    final image = File(p.join(root.path, 'repairs/photo48.png'));
    await image.writeAsString('Current image');
    failInstalledOpen = true;
    await expectLater(
        BackupService.restoreEncryptedFromPath(backup.path, password: password),
        throwsStateError);
    expect((await db.query('clients')).single['name'],
        'Must survive failed restore');
    expect(await image.readAsString(), 'Current image');
    expect(await BackupService.lastRestoreAt(), isNull);
    expect(await AuthSessionService().restoreSession(), isNotNull);
    expect(await Directory('$livePath.restore-journal').exists(), isFalse);
  }, skip: skip);

  test('expired Owner can create/export but cannot replace workshop data',
      () async {
    await license(db, expired: true);
    await expectLater(LicenseRuntimeService().requireOperationalWrite(),
        throwsA(isA<ReadOnlyOperationException>()));
    final backup =
        await BackupService.createEncryptedBackup(password: password);
    await AuthorizationGuard.require(PermissionKeys.backupExport);
    await expectLater(
        BackupService.restoreEncryptedFromPath(backup.path, password: password),
        throwsA(isA<ReadOnlyOperationException>()));
    expect(await File(backup.path).exists(), isTrue);
    expect((await db.query('clients')).single['name'], 'Preserved client');
  }, skip: skip);
}
