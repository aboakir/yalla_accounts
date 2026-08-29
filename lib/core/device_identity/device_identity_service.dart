import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../identity/organization_identity_service.dart';
import '../services/db/db_service.dart';
import '../services/db/tables/device_identity_tables.dart';
import 'device_fingerprint_service.dart';
import 'device_identity.dart';
import 'device_identity_secret_store.dart';

typedef DeviceIdentityDatabaseProvider = Future<Database> Function();

class DeviceIdentityService {
  DeviceIdentityService({
    DeviceIdentityDatabaseProvider? databaseProvider,
    DeviceIdentitySecretStore? secretStore,
    DeviceFingerprintProvider? fingerprintProvider,
    Ed25519? algorithm,
    Uuid? uuid,
  })  : _databaseProvider = databaseProvider ?? (() => DBService.database),
        _secretStore = secretStore ?? FlutterSecureDeviceIdentitySecretStore(),
        _fingerprintProvider =
            fingerprintProvider ?? DefaultDeviceFingerprintProvider(),
        _algorithm = algorithm ?? Ed25519(),
        _uuid = uuid ?? const Uuid();

  final DeviceIdentityDatabaseProvider _databaseProvider;
  final DeviceIdentitySecretStore _secretStore;
  final DeviceFingerprintProvider _fingerprintProvider;
  final Ed25519 _algorithm;
  final Uuid _uuid;

  static const _activeSeedKey = 'yalla.device.ed25519.seed.v1';
  static const _activeInstallationKey = 'yalla.installation.id.v1';
  static const _pendingSeedKey = 'yalla.device.ed25519.seed.pending.v1';
  static const _pendingInstallationKey = 'yalla.installation.id.pending.v1';

  Future<DeviceIdentity> ensureCurrent() async {
    final db = await _databaseProvider();
    await DeviceIdentityTables.ensure(db);

    final rows = await db.query(
      'installation_identity',
      where: 'singleton_id = 1',
      limit: 1,
    );
    final row = rows.isEmpty ? null : rows.single;

    if (row != null) {
      final recovered = await _tryRecoverPending(row);
      if (recovered) {
        return _readAndVerify(db);
      }

      final active = await _tryReadActiveKeyPair(row);
      if (active != null) {
        return _identityFromRow(row);
      }

      final state = row['binding_state']?.toString() ?? 'UNBOUND';
      if (state == 'BOUND' || state == 'REVOKED') {
        throw DeviceIdentityRecoveryRequired(
          'The server-bound device key is unavailable or does not match. '
          'Reactivation is required; silent identity rotation is blocked.',
        );
      }
    }

    return _provisionNew(db, previous: row);
  }

  Future<DeviceProof> signChallenge(List<int> challenge) async {
    if (challenge.isEmpty) {
      throw ArgumentError.value(challenge, 'challenge', 'must not be empty');
    }
    final identity = await ensureCurrent();
    final seed = await _readSeed(_activeSeedKey);
    if (seed == null) {
      throw DeviceIdentityRecoveryRequired(
          'Device signing key is unavailable.');
    }
    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final signature = await _algorithm.sign(challenge, keyPair: keyPair);
    return DeviceProof(
      deviceId: identity.deviceId,
      algorithm: 'ED25519',
      signatureBase64Url: _b64Url(signature.bytes),
    );
  }

  Future<void> markBound() async {
    final db = await _databaseProvider();
    final identity = await ensureCurrent();
    final now = DateTime.now().toUtc().toIso8601String();
    final changed = await db.update(
      'installation_identity',
      {
        'binding_state': 'BOUND',
        'bound_at': now,
        'updated_at': now,
      },
      where: 'singleton_id = 1 AND device_id = ?',
      whereArgs: [identity.deviceId],
    );
    if (changed != 1) {
      throw StateError('Failed to bind SEC.005 device identity.');
    }
  }

  Future<DeviceIdentity> _provisionNew(
    Database db, {
    Map<String, Object?>? previous,
  }) async {
    final organizationId = await OrganizationIdentityService(
      databaseProvider: () async => db,
    ).requireOrganizationId();
    final fingerprint = await _fingerprintProvider.collect();
    final keyPair = await _algorithm.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    if (seed.length != 32) {
      throw StateError('Unexpected Ed25519 private seed length.');
    }
    final publicKey = await keyPair.extractPublicKey();
    final publicBytes = publicKey.bytes;

    final installationId = _uuid.v4();
    final deviceId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final generation = ((previous?['identity_generation'] as int?) ?? 0) + 1;
    final publicKeyEncoded = _b64Url(publicBytes);
    final publicKeyHash = sha256.convert(publicBytes).toString();

    await _secretStore.write(_pendingSeedKey, _b64Url(seed));
    await _secretStore.write(_pendingInstallationKey, installationId);

    try {
      await db.transaction((txn) async {
        final values = <String, Object?>{
          'singleton_id': 1,
          'organization_id': organizationId,
          'installation_id': installationId,
          'device_id': deviceId,
          'key_algorithm': 'ED25519',
          'public_key_b64url': publicKeyEncoded,
          'public_key_sha256': publicKeyHash,
          'fingerprint_sha256': fingerprint.sha256Hex,
          'platform': fingerprint.platform,
          'platform_version': fingerprint.platformVersion,
          'app_version': fingerprint.appVersion,
          'identity_generation': generation,
          'binding_state': 'UNBOUND',
          'bound_at': null,
          'created_at': previous?['created_at']?.toString() ?? now,
          'updated_at': now,
        };
        if (previous == null) {
          await txn.insert('installation_identity', values);
        } else {
          final changed = await txn.update(
            'installation_identity',
            values,
            where: 'singleton_id = 1',
          );
          if (changed != 1) {
            throw StateError('Device identity rotation failed.');
          }
        }
      });

      await _secretStore.write(_activeSeedKey, _b64Url(seed));
      await _secretStore.write(_activeInstallationKey, installationId);
      await _secretStore.delete(_pendingSeedKey);
      await _secretStore.delete(_pendingInstallationKey);
      return _readAndVerify(db);
    } catch (_) {
      // Keep pending material when DB already committed: _tryRecoverPending()
      // can promote it safely on the next attempt. If DB did not commit it is
      // harmless orphaned pending material and will be replaced next attempt.
      rethrow;
    }
  }

  Future<bool> _tryRecoverPending(Map<String, Object?> row) async {
    final expectedInstallation = row['installation_id']?.toString() ?? '';
    final pendingInstallation =
        await _secretStore.read(_pendingInstallationKey);
    final pendingSeed = await _readSeed(_pendingSeedKey);
    if (pendingInstallation != expectedInstallation || pendingSeed == null) {
      return false;
    }
    final keyPair = await _algorithm.newKeyPairFromSeed(pendingSeed);
    final publicKey = await keyPair.extractPublicKey();
    if (_b64Url(publicKey.bytes) != row['public_key_b64url']?.toString()) {
      return false;
    }
    await _secretStore.write(_activeSeedKey, _b64Url(pendingSeed));
    await _secretStore.write(_activeInstallationKey, expectedInstallation);
    await _secretStore.delete(_pendingSeedKey);
    await _secretStore.delete(_pendingInstallationKey);
    return true;
  }

  Future<SimpleKeyPair?> _tryReadActiveKeyPair(Map<String, Object?> row) async {
    final installation = await _secretStore.read(_activeInstallationKey);
    if (installation != row['installation_id']?.toString()) return null;
    final seed = await _readSeed(_activeSeedKey);
    if (seed == null) return null;
    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    if (_b64Url(publicKey.bytes) != row['public_key_b64url']?.toString()) {
      return null;
    }
    return keyPair;
  }

  Future<List<int>?> _readSeed(String key) async {
    final encoded = await _secretStore.read(key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = _b64UrlDecode(encoded);
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<DeviceIdentity> _readAndVerify(Database db) async {
    await DeviceIdentityTables.validate(db);
    final rows = await db.query(
      'installation_identity',
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (rows.length != 1) {
      throw StateError('SEC.005 device identity metadata is missing.');
    }
    final row = rows.single;
    if (await _tryReadActiveKeyPair(row) == null) {
      throw DeviceIdentityRecoveryRequired(
          'Device key does not match metadata.');
    }
    return _identityFromRow(row);
  }

  static DeviceIdentity _identityFromRow(Map<String, Object?> row) {
    return DeviceIdentity(
      organizationId: row['organization_id']!.toString(),
      installationId: row['installation_id']!.toString(),
      deviceId: row['device_id']!.toString(),
      publicKeyBase64Url: row['public_key_b64url']!.toString(),
      publicKeySha256: row['public_key_sha256']!.toString(),
      fingerprintSha256: row['fingerprint_sha256']!.toString(),
      platform: row['platform']!.toString(),
      platformVersion: row['platform_version']?.toString(),
      appVersion: row['app_version']!.toString(),
      identityGeneration: row['identity_generation'] as int,
      bindingState: row['binding_state']!.toString(),
      createdAt: DateTime.parse(row['created_at']!.toString()),
      boundAt: row['bound_at'] == null
          ? null
          : DateTime.parse(row['bound_at']!.toString()),
    );
  }

  static String _b64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _b64UrlDecode(String value) {
    final pad = (4 - value.length % 4) % 4;
    return base64Url.decode(value + List.filled(pad, '=').join());
  }
}
