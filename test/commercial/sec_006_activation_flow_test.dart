import 'package:yalla_accounts/core/licensing/lifecycle/subscription_access_policy.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/device_identity/device_fingerprint_service.dart';
import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_secret_store.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_service.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_transport.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/first_owner_bootstrap_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

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
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        platform: 'windows',
        platformVersion: 'test',
        appVersion: '1.0.0+1',
      );
}

class _DeviceGateway implements ActivationDeviceIdentityGateway {
  _DeviceGateway(this.service);
  final DeviceIdentityService service;

  @override
  Future<DeviceIdentity> ensureCurrent() => service.ensureCurrent();

  @override
  Future<DeviceProof> signChallenge(List<int> challenge) =>
      service.signChallenge(challenge);
}

class _FakeActivationTransport implements ActivationTransport {
  _FakeActivationTransport(
    this.algorithm,
    this.signingKey,
    this.signingPublicKey,
  );

  final Ed25519 algorithm;
  final SimpleKeyPair signingKey;
  final SimplePublicKey signingPublicKey;
  DeviceIdentity? identity;
  final List<int> proofBytes = utf8.encode(
    'SEC006-TEST-PROOF-BYTES-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ',
  );

  @override
  bool get isConfigured => true;

  @override
  Future<ActivationChallenge> beginFirstActivation({
    required String activationCode,
    required DeviceIdentity identity,
  }) async {
    expect(activationCode, 'YLA-TEST-ACTIVATION-0001');
    this.identity = identity;
    return ActivationChallenge(
      challengeId: '11111111-1111-4111-8111-111111111111',
      idempotencyKey: '22222222-2222-4222-8222-222222222222',
      proofBytesBase64Url: _b64(proofBytes),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<ActivationCompletion> completeFirstActivation({
    required ActivationChallenge challenge,
    required DeviceProof proof,
  }) async {
    final currentIdentity = identity!;
    final devicePublicBytes = _decode(currentIdentity.publicKeyBase64Url);
    final deviceProofValid = await algorithm.verify(
      proofBytes,
      signature: Signature(
        _decode(proof.signatureBase64Url),
        publicKey: SimplePublicKey(
          devicePublicBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    expect(deviceProofValid, isTrue);

    final publicKey = signingPublicKey;
    final now = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'schema_version': 1,
      'issuer': 'yalla-licensing',
      'license_id': '33333333-3333-4333-8333-333333333333',
      'organization_id': currentIdentity.organizationId,
      'subscription_id': '44444444-4444-4444-8444-444444444444',
      'device_id': currentIdentity.deviceId,
      'installation_id': currentIdentity.installationId,
      'device_public_key_sha256': currentIdentity.publicKeySha256,
      'issued_at': now.toIso8601String(),
      'not_before': now.subtract(const Duration(seconds: 1)).toIso8601String(),
      'expires_at': now.add(const Duration(days: 30)).toIso8601String(),
      'entitlement_revision': 7,
      'entitlements': <String, Object?>{
        'ACCOUNTING_CORE': true,
        'MAX_DEVICES': 2,
        'MAX_USERS': 5,
      },
    };
    final canonicalBytes = utf8.encode(_canonicalize(payload));
    final signature = await algorithm.sign(canonicalBytes, keyPair: signingKey);
    final publicHash = sha256.convert(publicKey.bytes).toString();

    return ActivationCompletion(
      activationId: '55555555-5555-4555-8555-555555555555',
      serverTime: now,
      licenseEnvelope: <String, Object?>{
        'typ': 'YALLA-LICENSE',
        'alg': 'EdDSA',
        'kid': 'YALLA-LIC-TEST01',
        'payload': payload,
        'payload_sha256': sha256.convert(canonicalBytes).toString(),
        'signature': _b64(signature.bytes),
      },
      verificationKeyset: <String, Object?>{
        'issuer': 'yalla-licensing',
        'generated_at': now.toIso8601String(),
        'keys': [
          <String, Object?>{
            'kid': 'YALLA-LIC-TEST01',
            'alg': 'EdDSA',
            'public_key': _b64(publicKey.bytes),
            'public_key_sha256': publicHash,
            'status': 'ACTIVE',
            'not_before':
                now.subtract(const Duration(minutes: 1)).toIso8601String(),
            'not_after': null,
            'revoked_at': null,
          },
        ],
      },
    );
  }
}

String _canonicalize(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is String) return jsonEncode(value);
  if (value is List) return '[${value.map(_canonicalize).join(',')}]';
  if (value is Map) {
    final map = value.map<String, Object?>(
      (key, item) => MapEntry(key.toString(), item),
    );
    final keys = map.keys.toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonicalize(map[k])}').join(',')}}';
  }
  throw StateError('Unsupported test canonical value: ${value.runtimeType}');
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> _decode(String value) {
  final padding = List.filled((4 - value.length % 4) % 4, '=').join();
  return base64Url.decode('$value$padding');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('SEC.006 blocks First Owner until verified online activation', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec006_');
    final path = '${temp.path}${Platform.pathSeparator}activation.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    await WorkshopSettingsService.createTable(db);
    Future<sq.Database> provider() async => db;
    final secretStore = _MemorySecretStore();
    final deviceService = DeviceIdentityService(
      databaseProvider: provider,
      secretStore: secretStore,
      fingerprintProvider: const _FixedFingerprint(),
    );
    final algorithm = Ed25519();
    final signingKey = await algorithm.newKeyPair();
    final signingPublicKey = await signingKey.extractPublicKey();
    final signingPublicHash = sha256.convert(signingPublicKey.bytes).toString();
    final verifier = LicenseEnvelopeVerifier(
      trustedPublicKeySha256: {signingPublicHash},
    );
    final state = ActivationStateRepository(
      databaseProvider: provider,
      deviceIdentityService: deviceService,
      verifier: verifier,
    );
    final users = UserService(
      databaseProvider: provider,
      firstOwnerActivationRepository: state,
    );
    final transport = _FakeActivationTransport(
      algorithm,
      signingKey,
      signingPublicKey,
    );
    final activation = ActivationService(
      deviceIdentity: _DeviceGateway(deviceService),
      transport: transport,
      stateRepository: state,
      verifier: verifier,
    );

    try {
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(65));
      await deviceService.ensureCurrent();
      expect(await state.hasUsableActivationForCurrentInstallation(), isFalse);

      await expectLater(
        users.registerUser(
          AppUser(
            id: 'ignored',
            name: 'owner-before-activation',
            email: '',
            role: 'owner',
            status: 'active',
            createdAt: DateTime.now(),
            isOwner: true,
          ),
          'OwnerBefore123',
        ),
        throwsA(isA<FirstOwnerBootstrapException>()),
      );

      final verified = await activation.activateFirstInstallation(
        'YLA-TEST-ACTIVATION-0001',
      );
      expect(verified.entitlementRevision, 7);
      expect(await state.hasUsableActivationForCurrentInstallation(), isTrue);

      final activationRow = (await db.query('license_activation_state')).single;
      expect(activationRow['status'], 'ACTIVE');
      expect(activationRow['license_id'], verified.licenseId);
      expect(activationRow['signed_license_envelope_json'], isNotNull);
      expect(
        activationRow.values.join('|'),
        isNot(contains('YLA-TEST-ACTIVATION-0001')),
      );

      final originalEnvelope =
          activationRow['signed_license_envelope_json']!.toString();
      // Every Stage 46 state is accepted only with a fresh Ed25519 signature.
      final signedBase = jsonDecode(originalEnvelope) as Map<String, dynamic>;
      final keyset = Map<String, Object?>.from(
          jsonDecode(activationRow['verification_keyset_json']!.toString())
              as Map);
      for (final status in SubscriptionAccessPolicy.statuses) {
        final payload = Map<String, Object?>.from(signedBase['payload'] as Map)
          ..['operational_status'] = status;
        final bytes = utf8.encode(_canonicalize(payload));
        final signature = await algorithm.sign(bytes, keyPair: signingKey);
        final envelope = <String, Object?>{
          ...signedBase,
          'payload': payload,
          'payload_sha256': sha256.convert(bytes).toString(),
          'signature': _b64(signature.bytes)
        };
        final checked = await verifier.verify(
            envelope: envelope,
            verificationKeyset: keyset,
            identity: await deviceService.ensureCurrent(),
            requireCurrentValidity: false);
        expect(checked.operationalStatus, status);
        final forgedPayload = {
          ...payload,
          'operational_status': 'ACTIVE',
          'entitlement_revision': 99
        };
        final forged = {
          ...envelope,
          'payload': forgedPayload,
          'payload_sha256': sha256
              .convert(utf8.encode(_canonicalize(forgedPayload)))
              .toString()
        };
        await expectLater(
            verifier.verify(
                envelope: forged,
                verificationKeyset: keyset,
                identity: await deviceService.ensureCurrent(),
                requireCurrentValidity: false),
            throwsA(isA<LicenseVerificationException>()));
      }
      final tampered = jsonDecode(originalEnvelope) as Map<String, dynamic>;
      final tamperedPayload =
          Map<String, dynamic>.from(tampered['payload'] as Map);
      tamperedPayload['expires_at'] = DateTime.now()
          .toUtc()
          .add(const Duration(days: 3650))
          .toIso8601String();
      tampered['payload'] = tamperedPayload;
      await db.update(
        'license_activation_state',
        {'signed_license_envelope_json': jsonEncode(tampered)},
        where: 'singleton_id = 1',
      );
      expect(
        await state.hasUsableActivationForCurrentInstallation(),
        isFalse,
        reason: 'A locally edited license must not become authoritative.',
      );
      await db.update(
        'license_activation_state',
        {'signed_license_envelope_json': originalEnvelope},
        where: 'singleton_id = 1',
      );
      expect(await state.hasUsableActivationForCurrentInstallation(), isTrue);

      final identityRow = (await db.query('installation_identity')).single;
      expect(identityRow['binding_state'], 'BOUND');

      final created = await users.registerUser(
        AppUser(
          id: 'ignored',
          name: 'owner-after-activation',
          email: '',
          role: 'owner',
          status: 'active',
          createdAt: DateTime.now(),
          isOwner: true,
        ),
        'OwnerAfter123',
      );
      expect(created, isTrue);
      expect(await users.hasAnyUsers(), isTrue);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
