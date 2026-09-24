import 'dart:convert';

import 'package:http/http.dart' as http;

import 'commercial_backend_models.dart';

class CommercialBackendClient {
  CommercialBackendClient({
    required Uri baseUri,
    http.Client? httpClient,
    this.allowInsecureLoopbackForTesting = false,
  })  : _baseUri = baseUri,
        _httpClient = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _httpClient;
  final bool allowInsecureLoopbackForTesting;

  Future<RegistrationResult> register({
    required Map<String, Object?> payload,
  }) async {
    final data = await _post('api/v1/register.php', payload);
    return RegistrationResult(
      customerId: _requiredString(data, 'customer_id'),
      customerCode: _requiredString(data, 'customer_code'),
      customerStatus: _requiredString(data, 'customer_status'),
      deviceRequestStatus: _requiredString(data, 'device_request_status'),
    );
  }

  Future<DeviceRequestResult> requestDevice({
    required Map<String, Object?> payload,
  }) async {
    final data = await _post('api/v1/device-request.php', payload);
    return DeviceRequestResult(
      deviceRequestId: _requiredString(data, 'device_request_id'),
      status: _requiredString(data, 'status'),
    );
  }

  Future<DeviceStatusResult> deviceStatus({
    required String requestId,
    required String activationSecret,
  }) async {
    final data = await _post('api/v1/device-status.php', {
      'device_request_id': requestId,
      'activation_secret': activationSecret,
    });
    return DeviceStatusResult(
      status: _requiredString(data, 'status'),
      customerId: _optionalString(data, 'customer_id'),
      deviceId: _optionalString(data, 'device_id'),
      installationId: _optionalString(data, 'installation_id'),
      deviceToken: _optionalString(data, 'device_token'),
    );
  }

  Future<LicenseCheckResult> licenseCheck({
    required String installationId,
    required String deviceToken,
    String? appVersion,
  }) async {
    final data = await _post('api/v1/license-check.php', {
      'installation_id': installationId,
      'device_token': deviceToken,
      if (appVersion != null) 'app_version': appVersion,
    });
    return LicenseCheckResult(
      customerId: _requiredString(data, 'customer_id'),
      customerCode: _requiredString(data, 'customer_code'),
      accessMode: _requiredString(data, 'access_mode'),
      subscriptionStatus: _requiredString(data, 'subscription_status'),
      deviceId: _requiredString(data, 'device_id'),
      serverTime:
          DateTime.parse(_requiredString(data, '__server_time')).toUtc(),
      leaseUntil: DateTime.tryParse(_optionalString(data, 'lease_until') ?? '')
          ?.toUtc(),
      leaseToken: _optionalString(data, 'lease_token'),
    );
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    _assertSecureBaseUri();
    final uri = _baseUri.resolve(path);
    final response = await _httpClient.post(
      uri,
      headers: const {
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    final decoded = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final errorMap = error is Map
          ? error.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const <String, Object?>{};
      throw CommercialBackendException(
        errorMap['code']?.toString() ?? 'HTTP_ERROR',
        errorMap['message']?.toString() ?? 'Commercial backend request failed.',
        statusCode: response.statusCode,
        requestId: decoded['request_id']?.toString(),
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw const CommercialBackendException(
        'INVALID_RESPONSE',
        'Commercial backend returned an invalid response.',
      );
    }
    final result = data.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    result['__server_time'] = decoded['server_time'];
    return result;
  }

  Map<String, Object?> _decodeResponse(http.Response response) {
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) {
        return raw.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}
    throw CommercialBackendException(
      'INVALID_JSON',
      'Commercial backend returned invalid JSON.',
      statusCode: response.statusCode,
    );
  }

  void _assertSecureBaseUri() {
    if (_baseUri.scheme == 'https' && _baseUri.host.isNotEmpty) return;
    final loopback = _baseUri.host == 'localhost' ||
        _baseUri.host == '127.0.0.1' ||
        _baseUri.host == '::1';
    if (allowInsecureLoopbackForTesting &&
        _baseUri.scheme == 'http' &&
        loopback) {
      return;
    }
    throw const CommercialBackendException(
      'INSECURE_BACKEND_URL',
      'Commercial backend URL must use HTTPS.',
    );
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = _optionalString(map, key);
    if (value == null || value.isEmpty) {
      throw CommercialBackendException(
        'INVALID_RESPONSE',
        'Missing backend field: $key.',
      );
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  void dispose() {
    _httpClient.close();
  }
}
