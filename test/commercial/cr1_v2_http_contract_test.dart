import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_transport.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_lifecycle_transport.dart';

String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
List<int> decode(String value) => base64Url.decode(base64Url.normalize(value));

Future<Map<String, dynamic>> _readFixtureInfo(
  StreamIterator<String> lines,
  Set<String> requiredKeys,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final remaining = deadline.difference(DateTime.now());
    if (!await lines.moveNext().timeout(remaining)) break;
    try {
      final decoded = jsonDecode(lines.current);
      if (decoded is Map) {
        final info = Map<String, dynamic>.from(decoded);
        if (requiredKeys.every(info.containsKey)) return info;
      }
    } catch (_) {}
  }
  throw StateError('Control V2 fixture metadata was not emitted.');
}

void main() {
  test(
      'V2 transports reject an absent authenticated identity before sending requests',
      () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final transport = HttpActivationTransport(
        baseUri: Uri.parse('http://127.0.0.1:1'),
        httpClient: client,
        allowInsecureLoopbackForTesting: true);
    expect(transport.isConfigured, false);
    final identity = DeviceIdentity(
        organizationId: const Uuid().v4(),
        installationId: const Uuid().v4(),
        deviceId: const Uuid().v4(),
        publicKeyBase64Url: 'a' * 43,
        publicKeySha256: 'a' * 64,
        fingerprintSha256: 'a' * 64,
        platform: 'Windows',
        appVersion: '1',
        identityGeneration: 1,
        bindingState: 'UNBOUND',
        createdAt: DateTime.now());
    await expectLater(
        transport.beginFirstActivation(
            activationCode: 'aB' * 22, identity: identity),
        throwsA(isA<ActivationTransportException>()
            .having((e) => e.message, 'message', contains('session'))));
  });
  final controlRoot = Platform.environment['YALLA_CR1_CONTROL_ROOT'];
  test(
      'real Control V2 activation and lifecycle verify with unchanged Accounts verifier',
      () async {
    final process = await Process.start(
        'node', ['test-support/accounts-v2-fixture.mjs'],
        workingDirectory: controlRoot);
    final errors = StringBuffer();
    final stderrSub =
        process.stderr.transform(utf8.decoder).listen(errors.write);
    Future<void>? stdoutDrain;
    addTearDown(() async {
      process.stdin.writeln('close');
      try {
        await process.exitCode.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        process.kill();
      }
      try {
        await stdoutDrain?.timeout(const Duration(seconds: 2));
      } catch (_) {}
      await stderrSub.cancel();
    });
    final lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    final info = await _readFixtureInfo(lines, {
      'base',
      'organization_id',
      'installation_id',
      'activation_code',
      'license_id',
      'signing_hash',
      'token',
    });
    stdoutDrain = () async {
      while (await lines.moveNext()) {}
    }();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final algorithm = Ed25519();
    final pair = await algorithm.newKeyPair();
    final public = await pair.extractPublicKey();
    final device = DeviceIdentity(
        organizationId: info['organization_id'],
        installationId: info['installation_id'],
        deviceId: const Uuid().v4(),
        publicKeyBase64Url: b64(public.bytes),
        publicKeySha256: hashes.sha256.convert(public.bytes).toString(),
        fingerprintSha256: 'a' * 64,
        platform: 'Windows',
        platformVersion: '11',
        appVersion: '1.0',
        identityGeneration: 1,
        bindingState: 'UNBOUND',
        createdAt: DateTime.now());
    Future<DeviceProof> proof(String bytes) async => DeviceProof(
        deviceId: device.deviceId,
        algorithm: 'ED25519',
        signatureBase64Url:
            b64((await algorithm.sign(decode(bytes), keyPair: pair)).bytes));
    var tokenCalls = 0;
    Future<String?> token() async {
      tokenCalls++;
      return info['token'] as String;
    }

    final activation = HttpActivationTransport(
        baseUri: Uri.parse(info['base']),
        httpClient: client,
        bearerTokenProvider: token,
        allowInsecureLoopbackForTesting: true);
    final challenge = await activation.beginFirstActivation(
        activationCode: info['activation_code'], identity: device);
    final signedProof = await proof(challenge.proofBytesBase64Url);
    final result = await activation.completeFirstActivation(
        challenge: challenge, proof: signedProof);
    final verifier =
        LicenseEnvelopeVerifier(trustedPublicKeySha256: {info['signing_hash']});
    final verified = await verifier.verify(
        envelope: result.licenseEnvelope,
        verificationKeyset: result.verificationKeyset,
        identity: device,
        now: result.serverTime);
    expect(verified.licenseId, info['license_id']);
    expect(verified.operationalStatus, 'TRIAL');
    final replay = await activation.completeFirstActivation(
        challenge: challenge, proof: signedProof);
    expect(replay.licenseEnvelope, result.licenseEnvelope);
    final lifecycle = HttpLicenseLifecycleTransport(
        baseUri: Uri.parse(info['base']),
        httpClient: client,
        bearerTokenProvider: token,
        allowInsecureLoopbackForTesting: true);
    final lc = await lifecycle.begin(
        action: 'VALIDATE',
        identity: device,
        licenseId: verified.licenseId,
        subscriptionId: verified.subscriptionId);
    final completion = await lifecycle.complete(
        challenge: lc, proof: await proof(lc.proofBytesBase64Url));
    final refreshed = await verifier.verify(
        envelope: completion.licenseEnvelope,
        verificationKeyset: completion.verificationKeyset,
        identity: device,
        now: completion.serverTime);
    expect(refreshed.deviceId, device.deviceId);
    expect(tokenCalls, 5);
  },
      skip: controlRoot == null
          ? 'Set YALLA_CR1_CONTROL_ROOT to run the cross-repository HTTP contract test.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)));
}
