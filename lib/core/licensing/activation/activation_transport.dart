import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/licensing/customer_bearer_token_provider.dart';

class ActivationTransportException implements Exception {
  const ActivationTransportException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ActivationTransportException: $message';
}

class ActivationChallenge {
  const ActivationChallenge({
    required this.challengeId,
    required this.idempotencyKey,
    required this.proofBytesBase64Url,
    required this.expiresAt,
  });

  final String challengeId;
  final String idempotencyKey;
  final String proofBytesBase64Url;
  final DateTime expiresAt;
}

class ActivationCompletion {
  const ActivationCompletion({
    required this.activationId,
    required this.licenseEnvelope,
    required this.verificationKeyset,
    required this.serverTime,
  });

  final String activationId;
  final Map<String, Object?> licenseEnvelope;
  final Map<String, Object?> verificationKeyset;
  final DateTime serverTime;
}

abstract class ActivationTransport {
  bool get isConfigured;

  /// SEC.010: despite the compatibility name, the server infers the
  /// authoritative activation kind from the one-time grant. The client never
  /// self-declares FIRST/ADD_DEVICE/REACTIVATION/DEVICE_REPLACEMENT.
  Future<ActivationChallenge> beginFirstActivation({
    required String activationCode,
    required DeviceIdentity identity,
  });

  Future<ActivationCompletion> completeFirstActivation({
    required ActivationChallenge challenge,
    required DeviceProof proof,
  });
}

class HttpActivationTransport implements ActivationTransport {
  HttpActivationTransport({
    this.bearerTokenProvider,
    Uri? baseUri,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.allowInsecureLoopbackForTesting = false,
  })  : _baseUri = baseUri ?? _environmentBaseUri(),
        _httpClient = httpClient ?? HttpClient();

  final Uri? _baseUri;
  final CustomerBearerTokenProvider? bearerTokenProvider;
  final HttpClient _httpClient;
  final Duration timeout;
  final bool allowInsecureLoopbackForTesting;

  static Uri? _environmentBaseUri() {
    const configured = String.fromEnvironment('YALLA_LICENSING_BASE_URL');
    final raw = configured.trim();
    if (raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }

  @override
  bool get isConfigured => _baseUri != null && bearerTokenProvider != null;

  @override
  Future<ActivationChallenge> beginFirstActivation({
    required String activationCode,
    required DeviceIdentity identity,
  }) async {
    final code = activationCode.trim();
    if (code.length < 32 || code.length > 128) {
      throw const ActivationTransportException(
          'Invalid activation code format.');
    }
    final idempotency = const Uuid().v4();
    final response = await _post(
      '/v1/accounts-integration/activation/challenge',
      {
        'contract_version': 2,
        'activation_code': code,
        'idempotency_key': idempotency,
        'device': identity.toRegistrationPayload(),
      },
    );
    return ActivationChallenge(
      challengeId: _requiredString(response, 'challenge_id'),
      idempotencyKey: response['idempotency_key']?.toString() ?? idempotency,
      proofBytesBase64Url: _requiredString(response, 'proof_bytes'),
      expiresAt: _requiredDate(response, 'expires_at'),
    );
  }

  @override
  Future<ActivationCompletion> completeFirstActivation({
    required ActivationChallenge challenge,
    required DeviceProof proof,
  }) async {
    if (!challenge.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const ActivationTransportException('Activation challenge expired.');
    }
    final response = await _post(
      '/v1/accounts-integration/activation/complete',
      {
        'contract_version': 2,
        'challenge_id': challenge.challengeId,
        'idempotency_key': challenge.idempotencyKey,
        'device_id': proof.deviceId,
        'proof': {
          'algorithm': proof.algorithm,
          'signature': proof.signatureBase64Url,
        },
      },
    );
    return ActivationCompletion(
      activationId: _requiredString(response, 'activation_id'),
      licenseEnvelope: _requiredMap(response, 'license_envelope'),
      verificationKeyset: _requiredMap(response, 'verification_keyset'),
      serverTime: _requiredDate(response, 'server_time'),
    );
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final base = _baseUri;
    if (base == null) {
      throw const ActivationTransportException(
        'Yalla Licensing Server is not configured in this build.',
      );
    }
    _assertSecureBaseUri(base);
    final token = await bearerTokenProvider?.call().timeout(timeout);
    if (token == null ||
        !RegExp(r'^[A-Za-z0-9._~-]{32,4096}$').hasMatch(token)) {
      throw const ActivationTransportException(
          'Authenticated customer session is required.');
    }
    final uri = base.resolve(path);
    try {
      final request = await _httpClient.postUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('x-yalla-client', 'yalla-accounts-desktop');
      request.headers.set('x-yalla-contract-version', '2');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(timeout);
      Object? decoded;
      try {
        decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
      } catch (_) {
        throw ActivationTransportException(
          'Licensing server returned invalid JSON.',
          statusCode: response.statusCode,
        );
      }
      if (decoded is! Map) {
        throw ActivationTransportException(
          'Licensing server returned an invalid response.',
          statusCode: response.statusCode,
        );
      }
      final map = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = map['message']?.toString().trim();
        throw ActivationTransportException(
          message?.isNotEmpty == true
              ? message!
              : 'Activation request rejected.',
          statusCode: response.statusCode,
        );
      }
      if (map['contract_version'] != 2 ||
          response.headers.value('x-yalla-contract-version') != '2') {
        throw const ActivationTransportException(
            'Unsupported licensing contract version.');
      }
      return map;
    } on ActivationTransportException {
      rethrow;
    } on TimeoutException {
      throw const ActivationTransportException('Licensing server timed out.');
    } on SocketException {
      throw const ActivationTransportException(
        'Internet connection or licensing server is unavailable.',
      );
    } on HandshakeException {
      throw const ActivationTransportException(
        'Secure connection to the licensing server failed.',
      );
    }
  }

  void _assertSecureBaseUri(Uri uri) {
    if (uri.scheme == 'https' && uri.host.isNotEmpty) return;
    final loopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (allowInsecureLoopbackForTesting && uri.scheme == 'http' && loopback) {
      return;
    }
    throw const ActivationTransportException(
      'Licensing server URL must use HTTPS.',
    );
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw ActivationTransportException('Missing server field: $key.');
    }
    return value;
  }

  static DateTime _requiredDate(Map<String, Object?> map, String key) {
    final value = DateTime.tryParse(map[key]?.toString() ?? '');
    if (value == null) {
      throw ActivationTransportException('Invalid server timestamp: $key.');
    }
    return value.toUtc();
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> map,
    String key,
  ) {
    final value = map[key];
    if (value is! Map) {
      throw ActivationTransportException('Missing server object: $key.');
    }
    return value.map<String, Object?>(
      (itemKey, itemValue) => MapEntry(itemKey.toString(), itemValue),
    );
  }
}
