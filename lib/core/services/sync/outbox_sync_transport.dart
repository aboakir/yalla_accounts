import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';

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
  final Duration timeout;
  final bool allowInsecureLoopbackForTesting;
  final SyncLicenseProvider _licenseProvider;
  final SyncIdentityProvider _identityProvider;
  final SyncChallengeSigner _signer;

  bool get isConfigured => _baseUri != null;

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

    final payloadHash =
        sha256.convert(utf8.encode(message.payloadJson)).toString();
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
    };

    final challengeResponse = await _post(
      '/v1/sync/challenge',
      <String, Object?>{
        'api_version': 1,
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
        'api_version': 1,
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
