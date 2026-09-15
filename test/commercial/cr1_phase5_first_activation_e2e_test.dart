import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/device_identity/device_fingerprint_service.dart';
import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_secret_store.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_service.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_transport.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/services/first_owner_bootstrap_service.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_config.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_secure_storage.dart';
import 'package:yalla_accounts/features/cloud_auth/supabase_identity_provider.dart';
import 'package:yalla_accounts/features/onboarding/approved_onboarding_activation_service.dart';
import 'package:yalla_accounts/features/onboarding/customer_onboarding_client.dart';
import 'package:yalla_accounts/features/onboarding/customer_onboarding_service.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

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
        platformVersion: '11-test',
        appVersion: '1.0.0+18',
      );
}

class _Gateway implements ActivationDeviceIdentityGateway {
  _Gateway(this.service);
  final DeviceIdentityService service;
  @override
  Future<DeviceIdentity> ensureCurrent() => service.ensureCurrent();
  @override
  Future<DeviceProof> signChallenge(List<int> challenge) =>
      service.signChallenge(challenge);
}

void main() {
  _NetworkBinding();
  final controlRoot = Platform.environment['YALLA_CR1_CONTROL_ROOT'];
  test(
      'Phase 5 first approved customer activates real device and closes owner gate',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('yalla-phase5-e2e-');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/accounts.db',
    );
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    final process = await Process.start(
      'node',
      ['test-support/onboarding-v4-fixture.mjs'],
      workingDirectory: controlRoot,
    );
    final errors = StringBuffer();
    final err = process.stderr.transform(utf8.decoder).listen(errors.write);
    addTearDown(() async {
      process.stdin.writeln('close');
      try {
        await process.exitCode.timeout(const Duration(seconds: 10));
      } catch (_) {
        process.kill();
      }
      await err.cancel();
    });
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    expect(await lines.moveNext().timeout(const Duration(seconds: 30)), true,
        reason: errors.toString());
    final info = jsonDecode(lines.current) as Map<String, dynamic>;

    const cloudConfig = CloudAuthConfig(
      url: 'https://phase4-auth.example.invalid',
      publicKey: 'sb_publishable_phase4_fixture_only',
      releaseReady: true,
    );
    final cloud = SupabaseClient(
      info['auth_base'],
      cloudConfig.publicKey,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: CloudPkceStorage(CloudSecureStorage('phase5-e2e')),
      ),
    );
    addTearDown(cloud.dispose);
    final identity = SupabaseIdentityProvider(cloudConfig, client: cloud);
    addTearDown(identity.dispose);
    final onboardingClient = CustomerOnboardingClient(
      baseUri: Uri.parse(info['base']),
      allowInsecureLoopbackForTesting: true,
      sessionProvider: identity.verifiedOnboardingSession,
    );
    addTearDown(onboardingClient.close);
    final onboarding = CustomerOnboardingService(
      client: onboardingClient,
      database: () async => db,
    );

    const email = 'phase5-owner@example.invalid';
    const password = 'phase5-cloud-password1';
    const draft = <String, Object?>{
      'owner_name': 'Phase Five Owner',
      'organization_name': 'Phase Five Workshop',
      'phone': '+970599555555',
      'country_code': 'PS',
      'city': 'Bethlehem',
      'address': 'Phase Five Street',
      'province': 'West Bank',
      'street': 'Phase Five Street',
    };
    await identity.signUp(email, password);
    await identity.verifySignupCode(email, '123456');
    await identity.signIn(email, password);
    final pending = await onboarding.submit(draft);
    expect(pending.status, 'PENDING');

    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final approval = await http.postUrl(Uri.parse(
      '${info['base']}/v1/control-center/customer-onboarding/approve',
    ));
    approval.headers.contentType = ContentType.json;
    (info['admin'] as Map).forEach(
      (key, value) => approval.headers.set(key as String, value),
    );
    approval.write(jsonEncode({'request_id': pending.requestId}));
    final approvalResponse = await approval.close();
    final approvalBody = jsonDecode(
      await utf8.decoder.bind(approvalResponse).join(),
    ) as Map<String, dynamic>;
    expect(approvalResponse.statusCode, 200, reason: '$approvalBody');
    final activationCode = approvalBody['activation_code']?.toString() ?? '';
    expect(activationCode.length, greaterThanOrEqualTo(32));

    final approved = await onboarding.refresh();
    expect(approved.status, 'APPROVED');
    expect(approved.data['started_at'], isNull);
    expect(approved.data['activation_status'], 'ISSUED');
    expect(await db.query('installation_identity'), isEmpty);

    final activationPreparation = ApprovedOnboardingActivationService(
      client: onboardingClient,
      database: () async => db,
    );
    final placeholderOrganization =
        (await db.query('organization_identity')).single['organization_id'];
    final tampered = Map<String, Object?>.from(approved.data)
      ..['organization_id'] = const Uuid().v4();
    await db.update('pending_customer_onboarding', {
      'response_json': jsonEncode(tampered),
    });
    await expectLater(
      activationPreparation.prepare(),
      throwsA(isA<ApprovedOnboardingActivationException>()
          .having((e) => e.code, 'code', 'CACHED_APPROVAL_MISMATCH')),
    );
    expect(
      (await db.query('organization_identity')).single['organization_id'],
      placeholderOrganization,
    );
    await db.update('pending_customer_onboarding', {
      'response_json': jsonEncode(approved.data),
    });
    final prepared = await activationPreparation.prepare();
    expect(prepared.data['organization_id'], approved.data['organization_id']);
    expect(
        (await activationPreparation.prepare()).requestId, prepared.requestId);
    final localOrganization =
        (await db.query('organization_identity')).single['organization_id'];
    expect(localOrganization, approved.data['organization_id']);
    expect(
      (await db.query('owner_bootstrap_state')).single['organization_id'],
      approved.data['organization_id'],
    );

    final secrets = _MemorySecretStore();
    final deviceService = DeviceIdentityService(
      databaseProvider: () async => db,
      secretStore: secrets,
      fingerprintProvider: const _FixedFingerprint(),
    );
    final verifier = LicenseEnvelopeVerifier(
      trustedPublicKeySha256: {info['license_key_sha256'] as String},
    );
    final repository = ActivationStateRepository(
      databaseProvider: () async => db,
      deviceIdentityService: deviceService,
      verifier: verifier,
    );
    final activationTransport = HttpActivationTransport(
      baseUri: Uri.parse(info['base']),
      bearerTokenProvider: identity.verifiedAccessToken,
      allowInsecureLoopbackForTesting: true,
    );
    final activation = ActivationService(
      deviceIdentity: _Gateway(deviceService),
      transport: activationTransport,
      stateRepository: repository,
      verifier: verifier,
    );

    const ownerRequest = FirstOwnerBootstrapRequest(
      ownerName: 'Phase Five Owner',
      email: email,
      password: 'Local-owner-password1',
      workshopName: 'Phase Five Workshop',
      workshopAddress: 'Phase Five Street',
      country: 'فلسطين',
      province: 'الضفة الغربية',
      city: 'Bethlehem',
      street: 'Phase Five Street',
      phone: '+970599555555',
    );
    final ownerService = FirstOwnerBootstrapService(
      databaseProvider: () async => db,
      activationStateRepository: repository,
    );
    await expectLater(ownerService.createFirstOwner(ownerRequest),
        throwsA(isA<FirstOwnerBootstrapException>()));
    expect(await db.query('users'), isEmpty);
    expect(await db.query('auth_sessions'), isEmpty);
    expect(await db.query('installation_identity'), isEmpty);
    final license = await activation.activateFirstInstallation(activationCode);
    expect(license.organizationId, approved.data['organization_id']);
    expect(license.subscriptionId, approved.data['subscription_id']);
    expect(license.licenseId, approved.data['license_id']);
    expect(license.operationalStatus, 'TRIAL');
    expect(await repository.hasUsableActivationForCurrentInstallation(), true);
    final installation = (await db.query('installation_identity')).single;
    expect(installation['binding_state'], 'BOUND');
    final receipt = (await db.query('license_activation_state')).single;
    expect(receipt['activation_id'], approved.data['activation_id']);
    expect(receipt['device_id'], installation['device_id']);
    expect(receipt['installation_id'], installation['installation_id']);
    final envelope = Map<String, Object?>.from(
        jsonDecode(receipt['signed_license_envelope_json'] as String) as Map);
    final keyset = Map<String, Object?>.from(
        jsonDecode(receipt['verification_keyset_json'] as String) as Map);
    final device = await deviceService.ensureCurrent();
    expect(
        (await verifier.verify(
                envelope: envelope,
                verificationKeyset: keyset,
                identity: device))
            .licenseId,
        license.licenseId);
    await expectLater(
        LicenseEnvelopeVerifier(trustedPublicKeySha256: {'0' * 64}).verify(
            envelope: envelope, verificationKeyset: keyset, identity: device),
        throwsA(isA<LicenseVerificationException>()));
    final tamperedEnvelope = {
      ...envelope,
      'signature': base64Url.encode(List<int>.filled(64, 0)).replaceAll('=', '')
    };
    await expectLater(
        verifier.verify(
            envelope: tamperedEnvelope,
            verificationKeyset: keyset,
            identity: device),
        throwsA(isA<LicenseVerificationException>()));

    final live = await onboarding.refresh();
    expect(live.data['activation_status'], 'REDEEMED');
    expect(live.data['started_at'], isNotNull);

    final owner = await FirstOwnerBootstrapService(
      databaseProvider: () async => db,
      activationStateRepository: repository,
    ).createFirstOwner(const FirstOwnerBootstrapRequest(
      ownerName: 'Phase Five Owner',
      email: email,
      password: 'Local-owner-password1',
      workshopName: 'Phase Five Workshop',
      workshopAddress: 'Phase Five Street',
      country: 'ظپظ„ط³ط·ظٹظ†',
      province: 'ط§ظ„ط¶ظپط© ط§ظ„ط؛ط±ط¨ظٹط©',
      city: 'Bethlehem',
      street: 'Phase Five Street',
      phone: '+970599555555',
    ));
    expect(owner.ownerUserId, isNotEmpty);
    expect((await db.query('users')).length, 1);
    await expectLater(ownerService.createFirstOwner(ownerRequest),
        throwsA(isA<FirstOwnerBootstrapException>()));
    expect((await db.query('users')).length, 1);

    final secondPair = await Ed25519().newKeyPair();
    final secondPublic = await secondPair.extractPublicKey();
    final secondDevice = DeviceIdentity(
      organizationId: approved.data['organization_id'] as String,
      installationId: const Uuid().v4(),
      deviceId: const Uuid().v4(),
      publicKeyBase64Url:
          base64Url.encode(secondPublic.bytes).replaceAll('=', ''),
      publicKeySha256: sha256.convert(secondPublic.bytes).toString(),
      fingerprintSha256: 'c' * 64,
      platform: 'windows',
      appVersion: '1.0.0+18',
      identityGeneration: 1,
      bindingState: 'UNBOUND',
      createdAt: DateTime.now().toUtc(),
    );
    await expectLater(
      activationTransport.beginFirstActivation(
        activationCode: activationCode,
        identity: secondDevice,
      ),
      throwsA(isA<ActivationTransportException>()),
    );
    await expectLater(
        activationTransport.beginFirstActivation(
          activationCode: activationCode,
          identity: device,
        ),
        throwsA(isA<ActivationTransportException>()));
    expect((await onboarding.refresh()).data['started_at'],
        live.data['started_at']);

    secrets.values.clear();
    await expectLater(
      deviceService.ensureCurrent(),
      throwsA(isA<DeviceIdentityRecoveryRequired>()),
    );
    await lines.cancel();
  },
      skip: controlRoot == null
          ? 'Set YALLA_CR1_CONTROL_ROOT to the Phase 5 Control Server path'
          : false,
      timeout: const Timeout(Duration(minutes: 3)));
}
