import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/licensing/customer_bearer_token_provider.dart';

class LicenseLifecycleTransportException implements Exception {
  const LicenseLifecycleTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'LicenseLifecycleTransportException: $message';
}

class LicenseLifecycleChallenge {
  const LicenseLifecycleChallenge({
    required this.challengeId,
    required this.proofBytesBase64Url,
    required this.expiresAt,
    required this.action,
  });

  final String challengeId;
  final String proofBytesBase64Url;
  final DateTime expiresAt;
  final String action;
}

class LicenseLifecycleCompletion {
  const LicenseLifecycleCompletion({
    required this.lifecycleEventId,
    required this.licenseEnvelope,
    required this.verificationKeyset,
    required this.serverTime,
  });

  final String lifecycleEventId;
  final Map<String, Object?> licenseEnvelope;
  final Map<String, Object?> verificationKeyset;
  final DateTime serverTime;
}

abstract class LicenseLifecycleTransport {
  bool get isConfigured;

  Future<LicenseLifecycleChallenge> begin({
    required String action,
    required DeviceIdentity identity,
    required String licenseId,
    required String subscriptionId,
  });

  Future<LicenseLifecycleCompletion> complete({
    required LicenseLifecycleChallenge challenge,
    required DeviceProof proof,
  });
}

class HttpLicenseLifecycleTransport implements LicenseLifecycleTransport {
  HttpLicenseLifecycleTransport({
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
    return raw.isEmpty ? null : Uri.tryParse(raw);
  }

  @override
  bool get isConfigured => _baseUri != null && bearerTokenProvider != null;

  @override
  Future<LicenseLifecycleChallenge> begin({
    required String action,
    required DeviceIdentity identity,
    required String licenseId,
    required String subscriptionId,
  }) async {
    final normalized = action.trim().toUpperCase();
    if (!const {'VALIDATE', 'RENEW'}.contains(normalized)) {
      throw const LicenseLifecycleTransportException(
        'Unsupported lifecycle action.',
      );
    }

    final response = await _post(
      '/v1/accounts-integration/license-lifecycle/challenge',
      <String, Object?>{
        'contract_version': 2,
        'action': normalized,
        'license_id': licenseId,
        'subscription_id': subscriptionId,
        'device': identity.toRegistrationPayload(),
      },
    );

    return LicenseLifecycleChallenge(
      challengeId: _requiredString(response, 'challenge_id'),
      proofBytesBase64Url: _requiredString(response, 'proof_bytes'),
      expiresAt: _requiredDate(response, 'expires_at'),
      action: normalized,
    );
  }

  @override
  Future<LicenseLifecycleCompletion> complete({
    required LicenseLifecycleChallenge challenge,
    required DeviceProof proof,
  }) async {
    if (!challenge.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const LicenseLifecycleTransportException(
        'License lifecycle challenge expired.',
      );
    }

    final response = await _post(
      '/v1/accounts-integration/license-lifecycle/complete',
      <String, Object?>{
        'contract_version': 2,
        'challenge_id': challenge.challengeId,
        'action': challenge.action,
        'device_id': proof.deviceId,
        'proof': <String, Object?>{
          'algorithm': proof.algorithm,
          'signature': proof.signatureBase64Url,
        },
      },
    );

    return LicenseLifecycleCompletion(
      lifecycleEventId: _requiredString(response, 'lifecycle_event_id'),
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
      throw const LicenseLifecycleTransportException(
        'Yalla Licensing Server is not configured in this build.',
      );
    }
    _assertSecureBaseUri(base);
    final token = await bearerTokenProvider?.call().timeout(timeout);
    if (token == null ||
        !RegExp(r'^[A-Za-z0-9._~-]{32,4096}$').hasMatch(token)) {
      throw const LicenseLifecycleTransportException(
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
        throw LicenseLifecycleTransportException(
          'Licensing server returned invalid JSON.',
          statusCode: response.statusCode,
        );
      }
      if (decoded is! Map) {
        throw LicenseLifecycleTransportException(
          'Licensing server returned an invalid response.',
          statusCode: response.statusCode,
        );
      }
      final map = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = map['message']?.toString().trim();
        throw LicenseLifecycleTransportException(
          message?.isNotEmpty == true
              ? message!
              : 'License lifecycle request rejected.',
          statusCode: response.statusCode,
        );
      }
      if (map['contract_version'] != 2 ||
          response.headers.value('x-yalla-contract-version') != '2') {
        throw const LicenseLifecycleTransportException(
            'Unsupported licensing contract version.');
      }
      return map;
    } on LicenseLifecycleTransportException {
      rethrow;
    } on TimeoutException {
      throw const LicenseLifecycleTransportException(
        'Licensing server timed out.',
      );
    } on SocketException {
      throw const LicenseLifecycleTransportException(
        'Internet connection or licensing server is unavailable.',
      );
    } on HandshakeException {
      throw const LicenseLifecycleTransportException(
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
    throw const LicenseLifecycleTransportException(
      'Licensing server URL must use HTTPS.',
    );
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw LicenseLifecycleTransportException('Missing server field: $key.');
    }
    return value;
  }

  static DateTime _requiredDate(Map<String, Object?> map, String key) {
    final value = DateTime.tryParse(map[key]?.toString() ?? '');
    if (value == null) {
      throw LicenseLifecycleTransportException(
        'Invalid server timestamp: $key.',
      );
    }
    return value.toUtc();
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> map,
    String key,
  ) {
    final value = map[key];
    if (value is! Map) {
      throw LicenseLifecycleTransportException(
        'Missing server object: $key.',
      );
    }
    return value.map<String, Object?>(
      (itemKey, itemValue) => MapEntry(itemKey.toString(), itemValue),
    );
  }
}
