import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/device_identity/device_fingerprint_service.dart';
import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_secret_store.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

class _MemorySecretStore implements DeviceIdentitySecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FixedFingerprint implements DeviceFingerprintProvider {
  const _FixedFingerprint();
  @override
  Future<DeviceFingerprintSnapshot> collect() async =>
      const DeviceFingerprintSnapshot(
        sha256Hex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        platform: 'windows',
        platformVersion: 'test',
        appVersion: '1.0.0+1',
      );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('SEC.005 creates stable identity and keeps private key out of SQLite',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec005_');
    final path = '${temp.path}${Platform.pathSeparator}identity.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    final store = _MemorySecretStore();
    final service = DeviceIdentityService(
      databaseProvider: () async => db,
      secretStore: store,
      fingerprintProvider: const _FixedFingerprint(),
    );

    try {
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(64));

      final first = await service.ensureCurrent();
      final second = await service.ensureCurrent();
      expect(second.installationId, first.installationId);
      expect(second.deviceId, first.deviceId);
      expect(second.publicKeyBase64Url, first.publicKeyBase64Url);
      expect(first.identityGeneration, 1);
      expect(first.bindingState, 'UNBOUND');

      final columns =
          await db.rawQuery('PRAGMA table_info(installation_identity)');
      final names = columns.map((e) => e['name']?.toString()).toSet();
      expect(names, isNot(contains('private_key')));
      expect(names, isNot(contains('private_seed')));
      expect(names, isNot(contains('secret_key')));

      final raw = (await db.query('installation_identity')).single;
      final serialized = jsonEncode(raw);
      final privateSeed = store.values['yalla.device.ed25519.seed.v1'];
      expect(privateSeed, isNotNull);
      expect(privateSeed, isNotEmpty);
      expect(serialized, isNot(contains(privateSeed!)));
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('SEC.005 cloned DB without secure secret rotates unbound identity',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec005_clone_');
    final path = '${temp.path}${Platform.pathSeparator}clone.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    final originalStore = _MemorySecretStore();
    final firstService = DeviceIdentityService(
      databaseProvider: () async => db,
      secretStore: originalStore,
      fingerprintProvider: const _FixedFingerprint(),
    );
    try {
      final first = await firstService.ensureCurrent();
      final clonedMachineStore = _MemorySecretStore();
      final cloneService = DeviceIdentityService(
        databaseProvider: () async => db,
        secretStore: clonedMachineStore,
        fingerprintProvider: const _FixedFingerprint(),
      );
      final rotated = await cloneService.ensureCurrent();
      expect(rotated.installationId, isNot(first.installationId));
      expect(rotated.deviceId, isNot(first.deviceId));
      expect(rotated.publicKeyBase64Url, isNot(first.publicKeyBase64Url));
      expect(rotated.identityGeneration, 2);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('SEC.005 bound identity refuses silent rotation and signs challenge',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec005_bound_');
    final path = '${temp.path}${Platform.pathSeparator}bound.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    final store = _MemorySecretStore();
    final service = DeviceIdentityService(
      databaseProvider: () async => db,
      secretStore: store,
      fingerprintProvider: const _FixedFingerprint(),
    );
    try {
      final identity = await service.ensureCurrent();
      final challenge = utf8.encode('sec005-proof-of-possession');
      final proof = await service.signChallenge(challenge);
      expect(proof.deviceId, identity.deviceId);
      expect(proof.algorithm, 'ED25519');

      final signatureBytes = base64Url.decode(
        proof.signatureBase64Url +
            List.filled((4 - proof.signatureBase64Url.length % 4) % 4, '=')
                .join(),
      );
      final publicBytes = base64Url.decode(
        identity.publicKeyBase64Url +
            List.filled((4 - identity.publicKeyBase64Url.length % 4) % 4, '=')
                .join(),
      );
      final ok = await Ed25519().verify(
        challenge,
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
        ),
      );
      expect(ok, isTrue);

      await service.markBound();
      store.values.clear();
      await expectLater(
        service.ensureCurrent(),
        throwsA(isA<DeviceIdentityRecoveryRequired>()),
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
