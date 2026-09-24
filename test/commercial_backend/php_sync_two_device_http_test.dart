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

class _DeviceFixture extends DeviceIdentityService {
  _DeviceFixture(this.identity, this.keyPair);
  final DeviceIdentity identity;
  final SimpleKeyPair keyPair;
  final Ed25519 algorithm = Ed25519();
  @override
  Future<DeviceIdentity> ensureCurrent() async => identity;
  @override
  Future<DeviceProof> signChallenge(List<int> challenge) async {
    final signature = await algorithm.sign(challenge, keyPair: keyPair);
    return DeviceProof(
      deviceId: identity.deviceId,
      algorithm: 'ED25519',
      signatureBase64Url: base64Url.encode(signature.bytes).replaceAll('=', ''),
    );
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
    final raw = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}: $decoded');
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

Future<void> _runPhp(String code) async {
  final result = await Process.run(
    'D:/xampp/php/php.exe',
    ['-r', code],
    environment: {
      ...Platform.environment,
      'YALLAH_DB_CONFIG': 'D:/YALLAH_BACKEND/config/database.test.php',
    },
  );
  if (result.exitCode != 0) {
    throw StateError('PHP CLI failed: ${result.stdout}\n${result.stderr}');
  }
}

String _secret(Random random) => base64Url
    .encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    )
    .replaceAll('=', '');

Future<({SimpleKeyPair pair, DeviceIdentity identity, String publicKey})>
    _newIdentity(
        String organizationId, String installationId, String deviceId) async {
  final algorithm = Ed25519();
  final pair = await algorithm.newKeyPair();
  final public = await pair.extractPublicKey();
  final encoded = base64Url.encode(public.bytes).replaceAll('=', '');
  return (
    pair: pair,
    publicKey: encoded,
    identity: DeviceIdentity(
      organizationId: organizationId,
      installationId: installationId,
      deviceId: deviceId,
      publicKeyBase64Url: encoded,
      publicKeySha256: sha256.convert(public.bytes).toString(),
      fingerprintSha256: sha256.convert(utf8.encode(deviceId)).toString(),
      platform: 'windows',
      appVersion: '1.0.3+22',
      identityGeneration: 1,
      bindingState: 'BOUND',
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

void main() {
  const enabled = bool.fromEnvironment('YALLAH_RUN_PHP_SYNC_HTTP');
  test(
    'two approved devices converge through PHP Sync V3',
    () async {
      const baseUrl = String.fromEnvironment(
        'YALLAH_PHP_SYNC_BASE',
        defaultValue: 'http://127.0.0.1:8080/yallah_backend/',
      );
      final base = Uri.parse(baseUrl);
      final uuid = const Uuid();
      final random = Random.secure();
      final phone =
          '+970598${List.generate(6, (_) => random.nextInt(10)).join()}';
      final orgA = uuid.v4(),
          installA = uuid.v4(),
          deviceA = uuid.v4(),
          requestA = uuid.v4();
      final idA = await _newIdentity(orgA, installA, deviceA);
      final activationA = _secret(random);
      final register = await _post(base, 'api/v1/register.php', {
        'business_name': 'Two Device Sync',
        'owner_name': 'Acceptance',
        'phone_e164': phone,
        'country_code': 'PS',
        'installation_id': installA,
        'organization_id': orgA,
        'device_id': deviceA,
        'public_key': idA.publicKey,
        'public_key_algorithm': 'ED25519',
        'public_key_sha256': idA.identity.publicKeySha256,
        'registration_request_id': requestA,
        'activation_secret': activationA,
        'platform': 'windows',
        'device_name': 'DEVICE-A',
        'app_version': '1.0.3+22',
      });
      final registration = register['data'] as Map<String, dynamic>;
      final customerId = registration['customer_id']!.toString();
      final customerCode = registration['customer_code']!.toString();
      try {
        await _runPhp(
            "require 'D:/YALLAH_BACKEND/app/bootstrap.php'; (new AdminCustomerService())->approve('$customerId','$requestA',1,1);");
        final statusA = await _post(base, 'api/v1/device-status.php', {
          'device_request_id': requestA,
          'activation_secret': activationA,
        });
        final tokenA =
            (statusA['data'] as Map<String, dynamic>)['device_token']!
                .toString();
        final orgB = uuid.v4(),
            installB = uuid.v4(),
            deviceB = uuid.v4(),
            requestB = uuid.v4();
        final idB = await _newIdentity(orgB, installB, deviceB);
        final activationB = _secret(random);
        await _post(base, 'api/v1/device-request.php', {
          'customer_code': customerCode,
          'installation_id': installB,
          'organization_id': orgB,
          'device_id': deviceB,
          'public_key': idB.publicKey,
          'public_key_algorithm': 'ED25519',
          'public_key_sha256': idB.identity.publicKeySha256,
          'device_request_id': requestB,
          'activation_secret': activationB,
          'platform': 'windows',
          'device_name': 'DEVICE-B',
          'app_version': '1.0.3+22',
        });
        await _runPhp(
            "require 'D:/YALLAH_BACKEND/app/bootstrap.php'; (new AdminDeviceService())->approve('$requestB','PAID_EXTRA',1);");
        final statusB = await _post(base, 'api/v1/device-status.php', {
          'device_request_id': requestB,
          'activation_secret': activationB,
        });
        final tokenB =
            (statusB['data'] as Map<String, dynamic>)['device_token']!
                .toString();

        final transportA = HttpSyncV3Transport(
          baseUri: base,
          bearerTokenProvider: () async => tokenA,
          deviceIdentityService: _DeviceFixture(idA.identity, idA.pair),
          allowInsecureLoopbackForTesting: true,
          phpCommercialBackend: true,
        );
        final transportB = HttpSyncV3Transport(
          baseUri: base,
          bearerTokenProvider: () async => tokenB,
          deviceIdentityService: _DeviceFixture(idB.identity, idB.pair),
          allowInsecureLoopbackForTesting: true,
          phpCommercialBackend: true,
        );
        final entityUuid = uuid.v4();
        final changeA = uuid.v4();
        final payloadA = {
          'display_name': 'Shared Party A',
          'role_codes': ['CUSTOMER']
        };
        final rowA = <String, Object?>{
          'change_id': changeA,
          'organization_id': orgA,
          'entity_type': 'party',
          'entity_id': 'a-local-1',
          'entity_uuid': entityUuid,
          'operation': 'UPSERT',
          'base_revision': 0,
          'revision': 1,
          'idempotency_key': 'a-$changeA',
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'payload_json': jsonEncode(payloadA),
        };
        final pushedA = await transportA.push([rowA]);
        expect(pushedA.results.single.disposition, 'ACKNOWLEDGED');
        final seq1 = pushedA.results.single.serverSequence!;
        final bootstrapB = await transportB.bootstrap();
        expect(bootstrapB.snapshotSequence, greaterThanOrEqualTo(seq1));
        expect(bootstrapB.hasMore, isFalse);
        final bootstrappedA =
            bootstrapB.changes.firstWhere((c) => c.changeId == changeA);
        expect(bootstrappedA.entityUuid, entityUuid);
        expect(bootstrappedA.revision, 1);
        expect(bootstrappedA.payload['display_name'], 'Shared Party A');

        final pulledB = await transportB.pull(afterServerSequence: 0);
        final fromA = pulledB.changes.firstWhere((c) => c.changeId == changeA);
        expect(fromA.entityUuid, entityUuid);
        expect(fromA.revision, 1);
        expect(fromA.payload['display_name'], 'Shared Party A');

        final changeB = uuid.v4();
        final payloadB = {
          'display_name': 'Shared Party B',
          'role_codes': ['CUSTOMER']
        };
        final rowB = <String, Object?>{
          'change_id': changeB,
          'organization_id': orgB,
          'entity_type': 'party',
          'entity_id': 'b-local-1',
          'entity_uuid': entityUuid,
          'operation': 'UPSERT',
          'base_revision': 1,
          'revision': 2,
          'idempotency_key': 'b-$changeB',
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'payload_json': jsonEncode(payloadB),
        };
        final pushedB = await transportB.push([rowB]);
        expect(pushedB.results.single.disposition, 'ACKNOWLEDGED');
        final seq2 = pushedB.results.single.serverSequence!;
        expect(seq2, greaterThan(seq1));
        final pulledA = await transportA.pull(afterServerSequence: seq1);
        final fromB = pulledA.changes.firstWhere((c) => c.changeId == changeB);
        expect(fromB.entityUuid, entityUuid);
        expect(fromB.revision, 2);
        expect(fromB.payload['display_name'], 'Shared Party B');

        final domainTypes = <String>[
          'vehicle',
          'repair',
          'purchase_invoice',
          'payment',
          'cheque',
          'inventory_movement',
          'insurance_policy',
          'payroll_run',
        ];
        final matrixRows = <Map<String, Object?>>[];
        final matrixUuids = <String, String>{};
        for (final type in domainTypes) {
          final domainUuid = uuid.v4();
          final domainChange = uuid.v4();
          matrixUuids[type] = domainUuid;
          matrixRows.add(<String, Object?>{
            'change_id': domainChange,
            'organization_id': orgA,
            'entity_type': type,
            'entity_id': 'http-$type',
            'entity_uuid': domainUuid,
            'operation': 'UPSERT',
            'base_revision': 0,
            'revision': 1,
            'idempotency_key': 'matrix-$domainChange',
            'occurred_at': DateTime.now().toUtc().toIso8601String(),
            'payload_json': jsonEncode({'domain': type, 'source': 'DEVICE-A'}),
          });
        }
        final matrixPush = await transportA.push(matrixRows);
        expect(matrixPush.results, hasLength(domainTypes.length));
        expect(
          matrixPush.results.every((r) => r.disposition == 'ACKNOWLEDGED'),
          isTrue,
        );
        final firstMatrixSequences =
            matrixPush.results.map((r) => r.serverSequence).toList();
        final matrixRetry = await transportA.push(matrixRows);
        expect(
          matrixRetry.results.map((r) => r.serverSequence).toList(),
          firstMatrixSequences,
        );
        final matrixPullB = await transportB.pull(afterServerSequence: seq2);
        for (final type in domainTypes) {
          final change = matrixPullB.changes.firstWhere(
            (c) => c.entityType == type && c.entityUuid == matrixUuids[type],
          );
          expect(change.revision, 1);
          expect(change.payload['domain'], type);
          expect(change.payload['source'], 'DEVICE-A');
        }
        print(
            'TWO_DEVICE_HTTP_PASS customer=$customerId seq1=$seq1 seq2=$seq2 domains=${domainTypes.join(',')}');
      } finally {
        await _runPhp(
            "require 'D:/YALLAH_BACKEND/app/bootstrap.php'; Database::connection()->prepare('DELETE FROM customers WHERE id=?')->execute(['$customerId']);");
      }
    },
    skip: enabled ? false : 'manual PHP two-device HTTP gate',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
