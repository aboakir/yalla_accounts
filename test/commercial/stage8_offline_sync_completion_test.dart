import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/core/services/sync/outbox_sync_coordinator.dart';
import 'package:yalla_accounts/core/services/sync/outbox_sync_transport.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';

class _AckTransport implements OutboxSyncTransport {
  final List<String> keys = <String>[];

  @override
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message) async {
    keys.add(message.idempotencyKey);
    return OutboxSyncAck(idempotencyKey: message.idempotencyKey);
  }
}

class _OfflineTransport implements OutboxSyncTransport {
  @override
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message) {
    throw const SocketException('offline');
  }
}

Future<void> _enqueue(Database db, String id) async {
  await OfflineOutboxService.enqueue(
    db,
    channel: OfflineOutboxService.channelSync,
    operation: 'UPSERT',
    entityType: 'repair',
    entityId: id,
    idempotencyKey: 'repair:$id:create',
    payload: {'entity_id': id, 'value': 1},
  );
}

List<int> _decodeBase64Url(String value) {
  final pad = (4 - value.length % 4) % 4;
  return base64Url.decode(value + List.filled(pad, '=').join());
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('crash while sending is recovered and sent once after restart',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await TechnicalTables.createAllTables(db);
    await _enqueue(db, 'r-crash');
    final row = (await db.query(TechnicalTables.outboxTable)).single;
    await OfflineOutboxService.markSending(db, row['id']!.toString());

    await OfflineOutboxService.resetInterruptedSending(db);
    final recovered = (await db.query(TechnicalTables.outboxTable)).single;
    expect(recovered['status'], 'failed');
    expect(recovered['sent'], 0);

    final transport = _AckTransport();
    final status = SyncStateService(pollInterval: const Duration(days: 1));
    final coordinator = OutboxSyncCoordinator(status: status);
    final result = await coordinator.drain(
      database: db,
      transportOverride: transport,
    );

    expect(result.sent, 1);
    expect(result.remaining, 0);
    expect(transport.keys, ['repair:r-crash:create']);

    final second = await coordinator.drain(
      database: db,
      transportOverride: transport,
    );
    expect(second.sent, 0);
    expect(transport.keys, hasLength(1));
  });

  test('offline mutation survives and reconnect does not duplicate', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await TechnicalTables.createAllTables(db);
    await _enqueue(db, 'r-reconnect');
    final status = SyncStateService(pollInterval: const Duration(days: 1));
    final coordinator = OutboxSyncCoordinator(status: status);

    final offline = await coordinator.drain(
      database: db,
      transportOverride: _OfflineTransport(),
    );
    expect(offline.sent, 0);
    expect(offline.failed, 1);

    final row = (await db.query(TechnicalTables.outboxTable)).single;
    expect(row['status'], 'failed');
    expect(row['sent'], 0);
    await db.update(
      TechnicalTables.outboxTable,
      {'next_attempt_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [row['id']],
    );

    final transport = _AckTransport();
    final reconnected = await coordinator.drain(
      database: db,
      transportOverride: transport,
    );
    expect(reconnected.sent, 1);
    expect(transport.keys, ['repair:r-reconnect:create']);

    await coordinator.drain(database: db, transportOverride: transport);
    expect(transport.keys, hasLength(1));
  });

  test('secure transport sends hash, idempotency and signed device proof',
      () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final publicB64 = base64Url.encode(publicKey.bytes).replaceAll('=', '');
    final identity = DeviceIdentity(
      organizationId: '11111111-1111-4111-8111-111111111111',
      installationId: '22222222-2222-4222-8222-222222222222',
      deviceId: '33333333-3333-4333-8333-333333333333',
      publicKeyBase64Url: publicB64,
      publicKeySha256: sha256.convert(publicKey.bytes).toString(),
      fingerprintSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      platform: 'windows',
      appVersion: '1.0.0+18',
      identityGeneration: 1,
      bindingState: 'BOUND',
      createdAt: DateTime.utc(2026, 9, 12),
    );

    final license = VerifiedLicense(
      licenseId: '44444444-4444-4444-8444-444444444444',
      organizationId: identity.organizationId,
      subscriptionId: '55555555-5555-4555-8555-555555555555',
      deviceId: identity.deviceId,
      installationId: identity.installationId,
      issuedAt: DateTime.utc(2026, 9, 12),
      notBefore: DateTime.utc(2026, 9, 12),
      expiresAt: DateTime.utc(2026, 10, 12),
      entitlementRevision: 1,
      entitlements: const {'sync': true},
      validationRequiredAt: DateTime.utc(2026, 10, 1),
      validationGraceUntil: DateTime.utc(2026, 10, 8),
    );
    final challengeBytes = List<int>.generate(32, (i) => i + 1);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? challengeBody;
    Map<String, dynamic>? completeBody;
    var proofVerified = false;

    server.listen((request) async {
      final raw = await utf8.decoder.bind(request).join();
      final body = jsonDecode(raw) as Map<String, dynamic>;

      if (request.uri.path == '/v1/sync/challenge') {
        challengeBody = body;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'challenge_id': '66666666-6666-4666-8666-666666666666',
          'proof_bytes': base64Url.encode(challengeBytes).replaceAll('=', ''),
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 2))
              .toIso8601String(),
        }));
        await request.response.close();
        return;
      }

      if (request.uri.path == '/v1/sync/complete') {
        completeBody = body;
        final proof = body['proof'] as Map<String, dynamic>;
        final signature = _decodeBase64Url(proof['signature']!.toString());
        proofVerified = await algorithm.verify(
          challengeBytes,
          signature: Signature(signature, publicKey: publicKey),
        );
        request.response.statusCode = proofVerified ? 200 : 403;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'accepted': proofVerified,
          'remote_id': '77777777-7777-4777-8777-777777777777',
          'idempotency_key': 'repair:r-secure:create',
        }));
        await request.response.close();
        return;
      }

      request.response.statusCode = 404;
      await request.response.close();
    });

    final transport = SecureServerOutboxSyncTransport(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      allowInsecureLoopbackForTesting: true,
      licenseProvider: () async => license,
      identityProvider: () async => identity,
      signer: (challenge) async {
        final signed = await algorithm.sign(challenge, keyPair: keyPair);
        return DeviceProof(
          deviceId: identity.deviceId,
          algorithm: 'ED25519',
          signatureBase64Url:
              base64Url.encode(signed.bytes).replaceAll('=', ''),
        );
      },
    );

    const rawPayload = '{"b":2,"a":1}';
    final envelope = OutboxSyncEnvelope(
      id: 'repair:r-secure:message',
      channel: 'sync',
      operation: 'UPSERT',
      entityType: 'repair',
      entityId: 'r-secure',
      idempotencyKey: 'repair:r-secure:create',
      payloadJson: rawPayload,
      payload: jsonDecode(rawPayload) as Map<String, dynamic>,
      attemptCount: 2,
    );

    final ack = await transport.send(envelope);
    await server.close(force: true);

    expect(ack.accepted, isTrue);
    expect(ack.idempotencyKey, envelope.idempotencyKey);
    expect(ack.remoteId, '77777777-7777-4777-8777-777777777777');
    expect(proofVerified, isTrue);
    expect(completeBody?['device_id'], identity.deviceId);

    final mutation = challengeBody?['message'] as Map<String, dynamic>;
    expect(challengeBody?['license_id'], license.licenseId);
    expect(challengeBody?['subscription_id'], license.subscriptionId);
    expect(mutation['payload_json'], rawPayload);
    expect(mutation['payload_sha256'],
        sha256.convert(utf8.encode(rawPayload)).toString());
    expect(mutation['idempotency_key'], envelope.idempotencyKey);
    expect(mutation['attempt_count'], 2);
  });
}
