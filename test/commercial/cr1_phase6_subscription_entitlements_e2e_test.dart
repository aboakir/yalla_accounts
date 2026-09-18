import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_transport.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/entitlements/commercial_entitlement_policy.dart';
import 'package:yalla_accounts/core/licensing/entitlements/signed_feature_authorization_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_lifecycle_transport.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/subscription_access_policy.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
List<int> _decode(String value) => base64Url.decode(base64Url.normalize(value));

// Consumer boundary fed exclusively by the just-verified real HTTP envelope.
class _SignedRuntime extends LicenseRuntimeService {
  _SignedRuntime(this.license);
  final VerifiedLicense license;
  @override
  Future<LicenseRuntimeDecision> refreshFromStoredLicense(
          {DateTime? now}) async =>
      LicenseRuntimeDecision(
          license: license,
          reason: 'verified Gate 6 envelope',
          mode: SubscriptionAccessPolicy.mode(
              license, now ?? DateTime.now().toUtc()));
}

class _Fixture {
  _Fixture(this.process, this.info, this.stdoutDrain, this.stderrSubscription);
  final Process process;
  final Map<String, dynamic> info;
  final Future<void> stdoutDrain;
  final StreamSubscription<String> stderrSubscription;

  Future<void> close() async {
    process.stdin.writeln('close');
    try {
      await process.exitCode.timeout(const Duration(seconds: 10));
    } catch (_) {
      process.kill();
    }
    try {
      await stdoutDrain.timeout(const Duration(seconds: 2));
    } catch (_) {}
    await stderrSubscription.cancel();
  }
}

Future<_Fixture> _startFixture(String controlRoot) async {
  final process = await Process.start(
    'node',
    ['test-support/phase6-subscription-fixture.mjs'],
    workingDirectory: controlRoot,
  );
  final errors = StringBuffer();
  final stderr = process.stderr.transform(utf8.decoder).listen(errors.write);
  final lines = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
    throw StateError('Phase 6 fixture failed: $errors');
  }
  final info = jsonDecode(lines.current) as Map<String, dynamic>;
  final stdoutDrain = () async {
    while (await lines.moveNext()) {}
  }();
  return _Fixture(
    process,
    info,
    stdoutDrain,
    stderr,
  );
}

Future<Map<String, dynamic>> _action(
  Map<String, dynamic> info,
  String action, {
  Map<String, Object?> state = const {},
  int? futureDays,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('${info['control_base']}/test/subscription-action'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'action': action,
      'state': state,
      if (futureDays != null) 'future_days': futureDays,
    }));
    final response = await request.close();
    final body = jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw StateError('Phase 6 fixture action rejected: $body');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

class _CommercialClient {
  _CommercialClient({
    required this.info,
    required this.device,
    required this.keyPair,
    required this.httpClient,
    required this.activation,
    required this.lifecycle,
    required this.verifier,
  });

  final Map<String, dynamic> info;
  final DeviceIdentity device;
  final SimpleKeyPair keyPair;
  final HttpClient httpClient;
  final HttpActivationTransport activation;
  final HttpLicenseLifecycleTransport lifecycle;
  final LicenseEnvelopeVerifier verifier;
  final Ed25519 algorithm = Ed25519();

  Future<DeviceProof> proof(String bytes) async => DeviceProof(
        deviceId: device.deviceId,
        algorithm: 'ED25519',
        signatureBase64Url: _b64(
          (await algorithm.sign(_decode(bytes), keyPair: keyPair)).bytes,
        ),
      );

  Future<VerifiedLicense> activate() async {
    final challenge = await activation.beginFirstActivation(
      activationCode: info['activation_code'] as String,
      identity: device,
    );
    final completion = await activation.completeFirstActivation(
      challenge: challenge,
      proof: await proof(challenge.proofBytesBase64Url),
    );
    final verified = await verifier.verify(
      envelope: completion.licenseEnvelope,
      verificationKeyset: completion.verificationKeyset,
      identity: device,
      now: completion.serverTime,
    );
    await assertAuthority(verified);
    return verified;
  }

  Future<VerifiedLicense> validate(VerifiedLicense current) async {
    final challenge = await lifecycle.begin(
      action: 'VALIDATE',
      identity: device,
      licenseId: current.licenseId,
      subscriptionId: current.subscriptionId,
    );
    final completion = await lifecycle.complete(
      challenge: challenge,
      proof: await proof(challenge.proofBytesBase64Url),
    );
    final verified = await verifier.verify(
      envelope: completion.licenseEnvelope,
      verificationKeyset: completion.verificationKeyset,
      identity: device,
      now: completion.serverTime,
    );
    await assertAuthority(verified);
    return verified;
  }

  Future<void> assertAuthority(VerifiedLicense license) async {
    final snapshot = await _action(info, 'SNAPSHOT');
    final effective = snapshot['effective'] as Map;
    expect(
        license.operationalStatus, (snapshot['subscription'] as Map)['status']);
    expect(license.entitlementRevision, effective['revision']);
    expect(license.entitlements['PLAN_CODE'], effective['effective_plan_code']);
    expect(license.entitlements['ACCESS_ALLOWED'], effective['access_allowed']);
    expect(license.entitlements['MAX_USERS'], effective['max_users']);
    expect(license.entitlements['MAX_DEVICES'], effective['max_devices']);
    final service = SignedFeatureAuthorizationService(
        runtimeService: _SignedRuntime(license));
    for (final feature in [
      'ACCOUNTING_CORE',
      'WORKSHOP_REPAIRS',
      'PRO_FEATURE'
    ]) {
      final enabled = (effective['enabled_features'] as List).contains(feature);
      expect(license.entitlements[feature] == true, enabled);
      var invoked = false;
      Future<void> operation() async {
        invoked = true;
      }

      if (enabled &&
          effective['access_allowed'] == true &&
          SubscriptionAccessPolicy.mode(license, DateTime.now().toUtc()) ==
              'WRITABLE') {
        await service.execute(feature, operation);
        expect(invoked, isTrue);
      } else {
        await expectLater(service.execute(feature, operation),
            throwsA(isA<SignedFeatureDenied>()));
        expect(invoked, isFalse);
      }
    }
  }

  void close() => httpClient.close(force: true);
}

Future<_CommercialClient> _client(Map<String, dynamic> info) async {
  final algorithm = Ed25519();
  final pair = await algorithm.newKeyPair();
  final public = await pair.extractPublicKey();
  final device = DeviceIdentity(
    organizationId: info['organization_id'] as String,
    installationId: info['installation_id'] as String,
    deviceId: const Uuid().v4(),
    publicKeyBase64Url: _b64(public.bytes),
    publicKeySha256: hashes.sha256.convert(public.bytes).toString(),
    fingerprintSha256: 'd' * 64,
    platform: 'Windows',
    platformVersion: '11',
    appVersion: '1.0.0+18',
    identityGeneration: 1,
    bindingState: 'UNBOUND',
    createdAt: DateTime.now().toUtc(),
  );
  final http = HttpClient();
  Future<String?> token() async => info['token'] as String;
  final base = Uri.parse(info['base'] as String);
  return _CommercialClient(
    info: info,
    device: device,
    keyPair: pair,
    httpClient: http,
    activation: HttpActivationTransport(
      baseUri: base,
      httpClient: http,
      bearerTokenProvider: token,
      allowInsecureLoopbackForTesting: true,
    ),
    lifecycle: HttpLicenseLifecycleTransport(
      baseUri: base,
      httpClient: http,
      bearerTokenProvider: token,
      allowInsecureLoopbackForTesting: true,
    ),
    verifier: LicenseEnvelopeVerifier(
      trustedPublicKeySha256: {info['signing_hash'] as String},
    ),
  );
}

void _expectCommercial(
  VerifiedLicense license, {
  required String status,
  required String plan,
  required bool writable,
  bool? proFeature,
}) {
  expect(CommercialEntitlementPolicy.evaluate(license).valid, isTrue);
  expect(CommercialEntitlementPolicy.planCode(license), plan);
  expect(license.operationalStatus, status);
  expect(
    SubscriptionAccessPolicy.mode(license, license.issuedAt),
    writable ? LicenseRuntimeMode.writable : isNot(LicenseRuntimeMode.writable),
  );
  if (proFeature != null) {
    expect(CommercialEntitlementPolicy.isEnabled(license, 'PRO_FEATURE'),
        proFeature);
  }
}

void main() {
  final controlRoot = Platform.environment['YALLA_CR1_CONTROL_ROOT'];

  test('Phase 6 Gate matrix is reflected through signed Accounts authority',
      () async {
    final fixture = await _startFixture(controlRoot!);
    addTearDown(fixture.close);
    final client = await _client(fixture.info);
    addTearDown(client.close);

    var license = await client.activate();
    _expectCommercial(license, status: 'TRIAL', plan: 'PRO', writable: true);

    await _action(fixture.info, 'SUBSCRIPTION.CHANGE_PLAN',
        state: const {'plan_code': 'FREE'});
    license = await client.validate(license);
    _expectCommercial(license,
        status: 'TRIAL', plan: 'FREE', writable: true, proFeature: false);
    expect(license.entitlements['MAX_USERS'], 1);
    expect(license.entitlements['MAX_DEVICES'], 1);

    await _action(fixture.info, 'SUBSCRIPTION.CHANGE_PLAN',
        state: const {'plan_code': 'PRO'});
    license = await client.validate(license);
    _expectCommercial(license,
        status: 'TRIAL', plan: 'PRO', writable: true, proFeature: true);
    expect(license.entitlements['MAX_USERS'], 10);
    expect(license.entitlements['MAX_DEVICES'], 5);

    await _action(fixture.info, 'SUBSCRIPTION.TRIAL_CONVERT_TO_PAID');
    license = await client.validate(license);
    _expectCommercial(license, status: 'ACTIVE', plan: 'PRO', writable: true);
    await _action(fixture.info, 'SUBSCRIPTION.CANCEL');
    license = await client.validate(license);
    _expectCommercial(license,
        status: 'CANCELLED', plan: 'FREE', writable: false);
    await _action(fixture.info, 'SUBSCRIPTION.RESTORE');
    license = await client.validate(license);
    _expectCommercial(license, status: 'ACTIVE', plan: 'PRO', writable: true);

    await _action(fixture.info, 'SUBSCRIPTION.SUSPEND');
    license = await client.validate(license);
    _expectCommercial(license,
        status: 'SUSPENDED', plan: 'FREE', writable: false);
    expect(license.entitlements['ACCESS_ALLOWED'], false);

    await _action(fixture.info, 'SUBSCRIPTION.REACTIVATE');
    license = await client.validate(license);
    _expectCommercial(license, status: 'ACTIVE', plan: 'PRO', writable: true);
    expect(license.entitlements['ACCESS_ALLOWED'], true);

    await _action(fixture.info, 'EXPIRE', futureDays: 15);
    license = await client.validate(license);
    _expectCommercial(license,
        status: 'EXPIRED', plan: 'FREE', writable: false);
    expect(license.entitlements['ACCESS_ALLOWED'], false);

    await _action(
      fixture.info,
      'SUBSCRIPTION.RENEW',
      state: const {'renewal_days': 30},
      futureDays: 15,
    );
    license = await client.validate(license);
    _expectCommercial(license, status: 'ACTIVE', plan: 'PRO', writable: true);
  },
      skip: controlRoot == null
          ? 'Set YALLA_CR1_CONTROL_ROOT to the Phase 6 Control Server path'
          : false,
      timeout: const Timeout(Duration(minutes: 3)));

  test('Phase 6 TRIAL to EXPIRED is signed and read-only in Accounts',
      () async {
    final fixture = await _startFixture(controlRoot!);
    addTearDown(fixture.close);
    final client = await _client(fixture.info);
    addTearDown(client.close);
    var license = await client.activate();
    _expectCommercial(license, status: 'TRIAL', plan: 'PRO', writable: true);
    await _action(fixture.info, 'EXPIRE', futureDays: 15);
    license = await client.validate(license);
    _expectCommercial(license,
        status: 'EXPIRED', plan: 'FREE', writable: false);
    expect(license.entitlements['ACCESS_ALLOWED'], false);
  },
      skip: controlRoot == null
          ? 'Set YALLA_CR1_CONTROL_ROOT to the Phase 6 Control Server path'
          : false,
      timeout: const Timeout(Duration(minutes: 3)));
}
