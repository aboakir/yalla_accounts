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
      emailVerified: _bool(data, 'email_verified'),
      verificationRequired: _bool(data, 'verification_required'),
      emailMasked: _optionalString(data, 'email_masked'),
    );
  }

  Future<EmailVerificationResult> verifyEmail({
    required String requestId,
    required String activationSecret,
    required String code,
  }) async {
    final data = await _post('api/v1/email-verify.php', {
      'registration_request_id': requestId,
      'activation_secret': activationSecret,
      'code': code.trim(),
    });
    return EmailVerificationResult(
      emailVerified: _bool(data, 'email_verified'),
      emailMasked: _optionalString(data, 'email_masked'),
      verificationRequired: _bool(data, 'verification_required'),
    );
  }

  Future<EmailVerificationResult> resendEmailVerification({
    required String requestId,
    required String activationSecret,
  }) async {
    final data = await _post('api/v1/email-resend.php', {
      'registration_request_id': requestId,
      'activation_secret': activationSecret,
    });
    return EmailVerificationResult(
      emailVerified: _bool(data, 'email_verified'),
      emailMasked: _optionalString(data, 'email_masked'),
      verificationRequired: _bool(data, 'verification_required'),
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
      emailVerified: _bool(data, 'email_verified'),
      emailMasked: _optionalString(data, 'email_masked'),
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
      leaseUntil: _date(data['lease_until']),
      leaseToken: _optionalString(data, 'lease_token'),
      phoneE164: _optionalString(data, 'phone_e164'),
      businessName: _optionalString(data, 'business_name'),
      ownerName: _optionalString(data, 'owner_name'),
      email: _optionalString(data, 'email'),
      emailVerified: _bool(data, 'email_verified'),
      organizationId: _optionalString(data, 'organization_id'),
      subscriptionId: _optionalString(data, 'subscription_id'),
      planCode: _optionalString(data, 'plan'),
      planName: _optionalString(data, 'plan_name'),
      billingPeriod: _optionalString(data, 'billing_period') ?? 'MONTHLY',
      monthlyPrice: _double(data['monthly_price']),
      annualPrice: _double(data['annual_price']),
      currency: _optionalString(data, 'currency') ?? 'USD',
      startsAt: _date(data['starts_at']),
      expiresAt: _date(data['expires_at']),
      graceUntil: _date(data['grace_until']),
      entitlementRevision: _int(data['entitlement_revision']),
      features: _featureMap(data['features']),
      limits: _limitMap(data['limits']),
      availablePlans: _planList(data['available_plans']),
      maxUsers: _int(data['max_users']),
      usersUsed: _int(data['users_used']),
      maxDevices: _int(data['max_devices']),
      activeDevices: _int(data['active_devices']),
    );
  }

  Future<EntitlementCheckResult> entitlementCheck({
    required String installationId,
    required String deviceToken,
    required String feature,
    String action = 'WRITE',
    String? limitCode,
    int delta = 0,
  }) async {
    final data = await _post('api/v1/entitlement-check.php', {
      'installation_id': installationId,
      'device_token': deviceToken,
      'feature': feature,
      'action': action,
      if (limitCode != null) 'limit_code': limitCode,
      'delta': delta,
    });
    return EntitlementCheckResult(
      status: _requiredString(data, 'status').toUpperCase(),
    );
  }

  Future<PasswordResetChallengeResult> requestPasswordReset({
    required String installationId,
    required String deviceToken,
  }) async {
    final data = await _post('api/v1/password-reset-request.php', {
      'installation_id': installationId,
      'device_token': deviceToken,
    });
    return PasswordResetChallengeResult(
      challengeId: _requiredString(data, 'challenge_id'),
      emailMasked: _requiredString(data, 'email_masked'),
      expiresAt: DateTime.parse(_requiredString(data, 'expires_at')).toUtc(),
    );
  }

  Future<PasswordResetGrantResult> verifyPasswordReset({
    required String installationId,
    required String deviceToken,
    required String challengeId,
    required String code,
  }) async {
    final data = await _post('api/v1/password-reset-verify.php', {
      'installation_id': installationId,
      'device_token': deviceToken,
      'challenge_id': challengeId,
      'code': code.trim(),
    });
    return PasswordResetGrantResult(
      resetGrant: _requiredString(data, 'reset_grant'),
      expiresAt:
          DateTime.parse(_requiredString(data, 'grant_expires_at')).toUtc(),
    );
  }

  Future<bool> consumePasswordReset({
    required String installationId,
    required String deviceToken,
    required String resetGrant,
  }) async {
    final data = await _post('api/v1/password-reset-consume.php', {
      'installation_id': installationId,
      'device_token': deviceToken,
      'reset_grant': resetGrant,
    });
    return _bool(data, 'authorized');
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
        _baseUri.host == '::1' ||
        _baseUri.host == '10.0.2.2';
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

  static bool _bool(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static Map<String, CommercialFeatureEntitlement> _featureMap(
    Object? raw,
  ) {
    if (raw is! Map) return const {};
    final out = <String, CommercialFeatureEntitlement>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = (entry.value as Map).map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      out[entry.key.toString()] =
          CommercialFeatureEntitlement.fromMap(entry.key.toString(), map);
    }
    return out;
  }

  static Map<String, CommercialLimitEntitlement> _limitMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, CommercialLimitEntitlement>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = (entry.value as Map).map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      out[entry.key.toString()] =
          CommercialLimitEntitlement.fromMap(entry.key.toString(), map);
    }
    return out;
  }

  static List<CommercialPlanOption> _planList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((entry) {
      final map = entry.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      return CommercialPlanOption.fromMap(map);
    }).toList(growable: false);
  }

  static DateTime? _date(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text.replaceFirst(' ', 'T'))?.toUtc();
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  void dispose() {
    _httpClient.close();
  }
}
