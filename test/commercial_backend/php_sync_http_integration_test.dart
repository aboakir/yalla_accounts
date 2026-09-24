// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';

class _FixtureIdentityService extends DeviceIdentityService {
  _FixtureIdentityService(this.value, this.keyPair);
  final DeviceIdentity value;
  final SimpleKeyPair keyPair;
  final Ed25519 algorithm = Ed25519();

  @override
  Future<DeviceIdentity> ensureCurrent() async => value;

  @override
  Future<DeviceProof> signChallenge(List<int> challenge) async {
    final signature = await algorithm.sign(challenge, keyPair: keyPair);
    return DeviceProof(
        deviceId: value.deviceId,
        algorithm: 'ED25519',
        signatureBase64Url:
            base64Url.encode(signature.bytes).replaceAll('=', ''));
  }
}

Future<Map<String, dynamic>> _post(
    Uri base, String path, Map<String, Object?> body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(base.resolve(path));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}: $decoded');
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

void main() {
  const enabled = bool.fromEnvironment('YALLAH_RUN_PHP_SYNC_HTTP');
  test('Flutter Sync V3 signs and PHP verifies over HTTP', () async {
    final base = Uri.parse('http://127.0.0.1:8080/yallah_backend/');
    final uuid = const Uuid();
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final publicEncoded = base64Url.encode(publicKey.bytes).replaceAll('=', '');
    final organizationId = uuid.v4();
    final installationId = uuid.v4();
    final deviceId = uuid.v4();
    final requestId = uuid.v4();
    final random = Random.secure();
    final phone =
        '+970599${List.generate(6, (_) => random.nextInt(10)).join()}';
    final activation = base64Url
        .encode(
          List<int>.generate(32, (_) => random.nextInt(256)),
        )
        .replaceAll('=', '');
    final register = await _post(base, 'api/v1/register.php', {
      'business_name': 'HTTP Flutter Sync',
      'owner_name': 'Integration Test',
      'phone_e164': phone,
      'country_code': 'PS',
      'installation_id': installationId,
      'organization_id': organizationId,
      'device_id': deviceId,
      'public_key': publicEncoded,
      'public_key_algorithm': 'ED25519',
      'public_key_sha256': sha256.convert(publicKey.bytes).toString(),
      'registration_request_id': requestId,
      'activation_secret': activation,
      'platform': 'windows',
      'device_name': 'HTTP-FLUTTER',
      'app_version': '1.0.3+22',
    });
    final data = register['data'] as Map<String, dynamic>;
    final customerId = data['customer_id']!.toString();
    print(
        'SYNC_HTTP_PENDING customer=$customerId request=$requestId phone=$phone');

    String? token;
    for (var i = 0; i < 120 && token == null; i++) {
      final status = await _post(base, 'api/v1/device-status.php', {
        'device_request_id': requestId,
        'activation_secret': activation,
      });
      final statusData = status['data'] as Map<String, dynamic>;
      if (statusData['status'] == 'APPROVED') {
        token = statusData['device_token']?.toString();
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(token, isNotNull, reason: 'admin approval did not arrive');

    final identity = DeviceIdentity(
      organizationId: organizationId,
      installationId: installationId,
      deviceId: deviceId,
      publicKeyBase64Url: publicEncoded,
      publicKeySha256: sha256.convert(publicKey.bytes).toString(),
      fingerprintSha256: sha256.convert(utf8.encode('http-fixture')).toString(),
      platform: 'windows',
      appVersion: '1.0.3+22',
      identityGeneration: 1,
      bindingState: 'BOUND',
      createdAt: DateTime.now().toUtc(),
    );
    final transport = HttpSyncV3Transport(
      baseUri: base,
      bearerTokenProvider: () async => token,
      deviceIdentityService: _FixtureIdentityService(identity, keyPair),
      allowInsecureLoopbackForTesting: true,
      phpCommercialBackend: true,
    );
    final entityUuid = uuid.v4();
    final changeId = uuid.v4();
    final payload = {
      'display_name': 'HTTP Party',
      'role_codes': ['CUSTOMER']
    };
    final row = <String, Object?>{
      'change_id': changeId,
      'organization_id': organizationId,
      'entity_type': 'party',
      'entity_id': 'http-local-1',
      'entity_uuid': entityUuid,
      'operation': 'UPSERT',
      'base_revision': 0,
      'revision': 1,
      'idempotency_key': 'http-$changeId',
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'payload_json': jsonEncode(payload),
    };
    final pushed = await transport.push([row]);
    expect(pushed.results.single.disposition, 'ACKNOWLEDGED');
    final sequence = pushed.results.single.serverSequence;
    expect(sequence, isNotNull);

    final repeated = await transport.push([row]);
    expect(repeated.results.single.serverSequence, sequence);
    final pulled = await transport.pull(afterServerSequence: 0);
    expect(pulled.changes.any((change) => change.changeId == changeId), isTrue);
    expect(
      pulled.changes
          .firstWhere((change) => change.changeId == changeId)
          .payload['display_name'],
      'HTTP Party',
    );
    print(
        'SYNC_HTTP_PASS customer=$customerId change=$changeId sequence=$sequence');
  },
      skip: enabled ? false : 'manual PHP HTTP integration gate',
      timeout: const Timeout(Duration(minutes: 2)));
}
