import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/customer_bearer_token_provider.dart';

class OutboxSyncEnvelope {
  const OutboxSyncEnvelope({
    required this.id,
    required this.channel,
    required this.operation,
    required this.entityType,
    required this.entityId,
    required this.idempotencyKey,
    required this.payloadJson,
    required this.payload,
    required this.attemptCount,
    this.changeId,
    this.entityUuid,
    this.baseRevision,
    this.revision,
    this.changeOperation,
    this.occurredAt,
    this.localUserId,
    this.snapshotJson,
  });

  final String id;
  final String channel;
  final String operation;
  final String entityType;
  final String entityId;
  final String idempotencyKey;
  final String payloadJson;
  final Map<String, dynamic> payload;
  final int attemptCount;
  final String? changeId;
  final String? entityUuid;
  final int? baseRevision;
  final int? revision;
  final String? changeOperation;
  final String? occurredAt;
  final String? localUserId;
  final String? snapshotJson;

  factory OutboxSyncEnvelope.fromRow(Map<String, dynamic> row) {
    String requiredText(String key) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw FormatException('Outbox message is missing $key.');
      }
      return value;
    }

    final payloadJson = requiredText('payload_json');
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) {
      throw const FormatException('Outbox payload must be a JSON object.');
    }

    return OutboxSyncEnvelope(
      id: requiredText('id'),
      channel: requiredText('channel'),
      operation: requiredText('operation'),
      entityType: requiredText('entity_type'),
      entityId: requiredText('entity_id'),
      idempotencyKey: requiredText('idempotency_key'),
      payloadJson: payloadJson,
      payload: Map<String, dynamic>.from(decoded),
      attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
      changeId: row['sync_change_id']?.toString(),
      entityUuid: row['sync_entity_uuid']?.toString(),
      revision: (row['sync_revision'] as num?)?.toInt(),
      baseRevision: row['sync_revision'] is num
          ? (row['sync_revision'] as num).toInt() - 1
          : null,
      changeOperation: row['sync_change_operation']?.toString(),
      occurredAt: row['sync_occurred_at']?.toString(),
      localUserId: row['sync_user_id']?.toString(),
      snapshotJson: row['sync_snapshot_json']?.toString(),
    );
  }
}

class OutboxSyncAck {
  const OutboxSyncAck({
    required this.idempotencyKey,
    this.accepted = true,
    this.remoteId,
  });

  final String idempotencyKey;
  final bool accepted;
  final String? remoteId;
}

abstract interface class OutboxSyncTransport {
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message);
}

class OutboxSyncProtocolException implements Exception {
  const OutboxSyncProtocolException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'OutboxSyncProtocolException: $message';
}

typedef SyncLicenseProvider = Future<VerifiedLicense?> Function();
typedef SyncIdentityProvider = Future<DeviceIdentity> Function();
typedef SyncChallengeSigner = Future<DeviceProof> Function(List<int> challenge);

class SecureServerOutboxSyncTransport implements OutboxSyncTransport {
  SecureServerOutboxSyncTransport({
    Uri? baseUri,
    HttpClient? httpClient,
    this.bearerTokenProvider,
    this.timeout = const Duration(seconds: 20),
    this.allowInsecureLoopbackForTesting = false,
    SyncLicenseProvider? licenseProvider,
    SyncIdentityProvider? identityProvider,
    SyncChallengeSigner? signer,
  })  : _baseUri = baseUri ?? _environmentBaseUri(),
        _httpClient = httpClient ?? HttpClient(),
        _licenseProvider = licenseProvider ??
            (() => ActivationStateRepository()
                .loadAuthenticLicenseForCurrentInstallation(
                    allowExpired: true)),
        _identityProvider =
            identityProvider ?? (() => DeviceIdentityService().ensureCurrent()),
        _signer = signer ??
            ((challenge) => DeviceIdentityService().signChallenge(challenge));

  final Uri? _baseUri;
  final HttpClient _httpClient;
  final CustomerBearerTokenProvider? bearerTokenProvider;
  final Duration timeout;
  final bool allowInsecureLoopbackForTesting;
  final SyncLicenseProvider _licenseProvider;
  final SyncIdentityProvider _identityProvider;
  final SyncChallengeSigner _signer;

  bool get isConfigured => _baseUri != null && bearerTokenProvider != null;

  static Uri? _environmentBaseUri() {
    const configured = String.fromEnvironment('YALLA_LICENSING_BASE_URL');
    final raw = configured.trim();
    return raw.isEmpty ? null : Uri.tryParse(raw);
  }

  @override
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message) async {
    final license = await _licenseProvider();
    if (license == null) {
      throw const OutboxSyncProtocolException(
        'No authentic signed license is available for sync.',
      );
    }

    final identity = await _identityProvider();
    if (identity.deviceId != license.deviceId ||
        identity.installationId != license.installationId ||
        identity.organizationId != license.organizationId) {
      throw const OutboxSyncProtocolException(
        'Device identity does not match the signed license.',
      );
    }

    final changeId = message.changeId?.trim() ?? '';
    final entityUuid = message.entityUuid?.trim() ?? '';
    final snapshotJson = message.snapshotJson?.trim() ?? '';
    final revision = message.revision;
    final baseRevision = message.baseRevision;
    final changeOperation = message.changeOperation?.trim() ?? '';
    final occurredAt = message.occurredAt?.trim() ?? '';
    if (changeId.isEmpty ||
        entityUuid.isEmpty ||
        snapshotJson.isEmpty ||
        revision == null ||
        baseRevision == null ||
        changeOperation.isEmpty ||
        occurredAt.isEmpty) {
      throw const OutboxSyncProtocolException(
        'Durable sync metadata is missing for this outbox message.',
      );
    }
    final payloadHash =
        sha256.convert(utf8.encode(message.payloadJson)).toString();
    final snapshotHash = sha256.convert(utf8.encode(snapshotJson)).toString();
    final mutation = <String, Object?>{
      'message_id': message.id,
      'channel': message.channel,
      'operation': message.operation.toUpperCase(),
      'entity_type': message.entityType,
      'entity_id': message.entityId,
      'idempotency_key': message.idempotencyKey,
      'payload_json': message.payloadJson,
      'payload_sha256': payloadHash,
      'attempt_count': message.attemptCount,
      'change_id': changeId,
      'entity_uuid': entityUuid,
      'base_revision': baseRevision,
      'revision': revision,
      'change_operation': changeOperation,
      'occurred_at': occurredAt,
      'local_user_id': message.localUserId,
      'snapshot_json': snapshotJson,
      'snapshot_sha256': snapshotHash,
    };

    final challengeResponse = await _post(
      '/v1/sync/challenge',
      <String, Object?>{
        'contract_version': 2,
        'license_id': license.licenseId,
        'subscription_id': license.subscriptionId,
        'device': identity.toRegistrationPayload(),
        'message': mutation,
      },
    );

    final challengeId = _requiredString(challengeResponse, 'challenge_id');
    final proofBytes = _decodeBase64Url(
      _requiredString(challengeResponse, 'proof_bytes'),
    );
    final expiresAt = _requiredDate(challengeResponse, 'expires_at');
    if (!expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const OutboxSyncProtocolException('Sync challenge expired.');
    }

    final proof = await _signer(proofBytes);
    if (proof.deviceId != identity.deviceId) {
      throw const OutboxSyncProtocolException(
        'Signed proof belongs to a different device.',
      );
    }

    final completion = await _post(
      '/v1/sync/complete',
      <String, Object?>{
        'contract_version': 2,
        'challenge_id': challengeId,
        'device_id': proof.deviceId,
        'proof': <String, Object?>{
          'algorithm': proof.algorithm,
          'signature': proof.signatureBase64Url,
        },
      },
    );

    return OutboxSyncAck(
      idempotencyKey: _requiredString(completion, 'idempotency_key'),
      accepted: completion['accepted'] == true,
      remoteId: completion['remote_id']?.toString(),
    );
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final base = _baseUri;
    if (base == null) {
      throw const OutboxSyncProtocolException(
        'Yalla Licensing Server is not configured in this build.',
      );
    }
    _assertSecureBaseUri(base);
    final uri = base.resolve(path);

    try {
      final request = await _httpClient.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final tokenProvider = bearerTokenProvider;
      if (tokenProvider == null) {
        throw const OutboxSyncProtocolException(
          'Authenticated customer session is required for sync.',
        );
      }
      final token = (await tokenProvider())?.trim() ?? '';
      if (token.isEmpty) {
        throw const OutboxSyncProtocolException(
          'Authenticated customer session is required for sync.',
        );
      }
      final identity = await _identityProvider();
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set('x-yalla-contract-version', '2');
      request.headers.set('x-yalla-installation-id', identity.installationId);
      request.headers.set('x-yalla-client', 'yalla-accounts-sync');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(timeout);

      Object? decoded;
      try {
        decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
      } catch (_) {
        throw OutboxSyncProtocolException(
          'Sync server returned invalid JSON.',
          statusCode: response.statusCode,
        );
      }
      if (decoded is! Map) {
        throw OutboxSyncProtocolException(
          'Sync server returned an invalid response.',
          statusCode: response.statusCode,
        );
      }

      final map = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          map['contract_version'] != 2) {
        throw OutboxSyncProtocolException(
          'Sync response contract version mismatch.',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = map['message']?.toString().trim();
        throw OutboxSyncProtocolException(
          message?.isNotEmpty == true ? message! : 'Sync request rejected.',
          statusCode: response.statusCode,
        );
      }
      return map;
    } on OutboxSyncProtocolException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } on HandshakeException catch (error) {
      throw SocketException('Secure sync connection failed: $error');
    }
  }

  void _assertSecureBaseUri(Uri uri) {
    if (uri.scheme == 'https' && uri.host.isNotEmpty) return;
    final loopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (allowInsecureLoopbackForTesting && uri.scheme == 'http' && loopback) {
      return;
    }
    throw const OutboxSyncProtocolException(
      'Sync server URL must use HTTPS.',
    );
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw OutboxSyncProtocolException('Missing server field: $key.');
    }
    return value;
  }

  static DateTime _requiredDate(Map<String, Object?> map, String key) {
    final value = DateTime.tryParse(map[key]?.toString() ?? '');
    if (value == null) {
      throw OutboxSyncProtocolException('Invalid server timestamp: $key.');
    }
    return value.toUtc();
  }

  static List<int> _decodeBase64Url(String value) {
    try {
      final pad = (4 - value.length % 4) % 4;
      return base64Url.decode(value + List.filled(pad, '=').join());
    } catch (_) {
      throw const OutboxSyncProtocolException(
        'Sync challenge proof is not valid base64url.',
      );
    }
  }
}
