import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final yallaAdminAuthServiceProvider = Provider<YallaAdminAuthService>(
  (ref) => YallaAdminAuthService(),
);

class YallaAdminIdentity {
  const YallaAdminIdentity({
    required this.email,
    required this.roles,
    required this.permissions,
    required this.authenticationLevel,
  });

  final String email;
  final List<String> roles;
  final List<String> permissions;
  final String authenticationLevel;

  bool get isSuperOwner => roles.contains('YALLA_SUPER_OWNER');
  bool get isYallaAdmin => roles.isNotEmpty;
}

enum YallaAdminLoginState {
  authenticated,
  mfaRequired,
  rejected,
  unavailable,
}

class YallaAdminLoginResult {
  const YallaAdminLoginResult._({
    required this.state,
    this.challengeId,
    this.identity,
    this.message,
  });

  final YallaAdminLoginState state;
  final String? challengeId;
  final YallaAdminIdentity? identity;
  final String? message;

  factory YallaAdminLoginResult.authenticated(YallaAdminIdentity identity) =>
      YallaAdminLoginResult._(
        state: YallaAdminLoginState.authenticated,
        identity: identity,
      );

  factory YallaAdminLoginResult.mfaRequired(String challengeId) =>
      YallaAdminLoginResult._(
        state: YallaAdminLoginState.mfaRequired,
        challengeId: challengeId,
      );

  factory YallaAdminLoginResult.rejected() => const YallaAdminLoginResult._(
        state: YallaAdminLoginState.rejected,
      );

  factory YallaAdminLoginResult.unavailable(String message) =>
      YallaAdminLoginResult._(
        state: YallaAdminLoginState.unavailable,
        message: message,
      );
}

class YallaAdminEnrollmentStart {
  const YallaAdminEnrollmentStart({
    required this.challengeId,
    this.totpProvisioningUri,
  });

  final String challengeId;
  final String? totpProvisioningUri;
}

class YallaAdminAuthException implements Exception {
  const YallaAdminAuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'YallaAdminAuthException: $message';
}

class CustomerPhoneOtpChallenge {
  const CustomerPhoneOtpChallenge({
    required this.challengeId,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
    required this.delivery,
  });

  final String challengeId;
  final int expiresInSeconds;
  final int resendAfterSeconds;
  final String delivery;
}

class CustomerPhoneVerification {
  const CustomerPhoneVerification({
    required this.challengeId,
    required this.phone,
    required this.verificationToken,
  });

  final String challengeId;
  final String phone;
  final String verificationToken;
}

/// Native SEC.015 Control Center authentication transport.
///
/// The desktop application and customer application share one executable and
/// one login screen, but Yalla administrator credentials remain server-side.
/// Session cookies are held only in this process memory. They are never written
/// to client preference/secure-persistence APIs, URLs, logs, or the customer DB.
class YallaAdminAuthService {
  YallaAdminAuthService({
    Uri? baseUri,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 12),
    this.allowInsecureLoopbackForTesting = const bool.fromEnvironment(
      'YALLA_ALLOW_INSECURE_LOOPBACK_FOR_TESTING',
      defaultValue: false,
    ),
  })  : _baseUri = baseUri ?? _environmentBaseUri(),
        _httpClient = httpClient ?? HttpClient();

  final Uri? _baseUri;
  final HttpClient _httpClient;
  final Duration timeout;
  final bool allowInsecureLoopbackForTesting;

  final Map<String, String> _sessionCookies = <String, String>{};
  String _csrfToken = '';
  YallaAdminIdentity? _identity;

  static Uri? _environmentBaseUri() {
    const configured = String.fromEnvironment('YALLA_LICENSING_BASE_URL');
    final raw = configured.trim();
    if (raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }

  bool get isConfigured => _baseUri != null;
  YallaAdminIdentity? get currentIdentity => _identity;

  Future<YallaAdminLoginResult> login({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) {
      return YallaAdminLoginResult.unavailable(
        'Yalla Licensing Server is not configured in this build.',
      );
    }

    clearInMemorySession();

    try {
      final payload = _requireMap(await _request(
        '/v1/control-center/auth/login',
        method: 'POST',
        body: <String, Object?>{
          'email': email.trim(),
          'password': password,
        },
        csrf: false,
      ));

      final status = payload['status']?.toString().toUpperCase();
      if (status == 'MFA_REQUIRED') {
        final challengeId = payload['challenge_id']?.toString().trim() ?? '';
        if (challengeId.isEmpty) {
          throw const YallaAdminAuthException(
            'Server did not return an MFA challenge.',
          );
        }
        return YallaAdminLoginResult.mfaRequired(challengeId);
      }

      final identity = await loadCurrentSession();
      return YallaAdminLoginResult.authenticated(identity);
    } on YallaAdminAuthException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        clearInMemorySession();
        return YallaAdminLoginResult.rejected();
      }
      clearInMemorySession();
      return YallaAdminLoginResult.unavailable(error.message);
    }
  }

  Future<YallaAdminIdentity> verifyTotp({
    required String challengeId,
    required String code,
  }) async {
    await _request(
      '/v1/control-center/auth/mfa/verify',
      method: 'POST',
      body: <String, Object?>{
        'challenge_id': challengeId,
        'method': 'TOTP',
        'proof': <String, Object?>{'code': code.trim()},
      },
      csrf: false,
    );
    return loadCurrentSession();
  }

  Future<YallaAdminIdentity> loadCurrentSession() async {
    final payload = _requireMap(await _request(
      '/v1/control-center/auth/session',
      csrf: false,
    ));

    final auth = _map(payload['authorization']);
    final roles = _stringList(payload['roles'] ?? auth['roles']);
    final permissions = _stringList(
      payload['permissions'] ?? auth['permissions'],
    );
    final email = (payload['email'] ?? auth['email'])?.toString().trim() ?? '';
    final level = (payload['authentication_level'] ??
            auth['authentication_level'] ??
            'AUTHENTICATED')
        .toString();

    if (roles.isEmpty) {
      throw const YallaAdminAuthException(
        'Authenticated server session has no Yalla administrative role.',
      );
    }

    final identity = YallaAdminIdentity(
      email: email,
      roles: roles,
      permissions: permissions,
      authenticationLevel: level,
    );
    _identity = identity;
    return identity;
  }

  Future<Object?> getControlCenter(String endpoint) {
    return _request(
      '/v1/control-center${_normalizedEndpoint(endpoint)}',
      csrf: false,
    );
  }

  Future<Map<String, Object?>> submitPrivilegedAction({
    required String actionCode,
    required String reason,
    String? organizationId,
    String? targetEntityType,
    String? targetEntityId,
    Map<String, Object?> requestedState = const <String, Object?>{},
    String? breakGlassGrantId,
    DateTime? expiresAt,
  }) {
    return _requestMap(
      '/v1/control-center/actions',
      method: 'POST',
      body: <String, Object?>{
        'action_code': actionCode.trim(),
        'organization_id': _nullIfEmpty(organizationId),
        'target_entity_type': _nullIfEmpty(targetEntityType),
        'target_entity_id': _nullIfEmpty(targetEntityId),
        'reason': reason.trim(),
        'requested_state': requestedState,
        'break_glass_grant_id': _nullIfEmpty(breakGlassGrantId),
        'expires_at': expiresAt?.toUtc().toIso8601String(),
      },
    );
  }

  Future<Map<String, Object?>> reauthenticateForBreakGlass({
    required String password,
    required String totpCode,
  }) {
    return _requestMap(
      '/v1/control-center/auth/re-auth',
      method: 'POST',
      body: <String, Object?>{
        'purpose': 'BREAK_GLASS',
        'password': password,
        'mfa_method': 'TOTP',
        'mfa_proof': <String, Object?>{'code': totpCode.trim()},
      },
    );
  }

  Future<Map<String, Object?>> openBreakGlass({
    required String organizationId,
    required String reason,
    required int durationMinutes,
    required String reauthContextId,
  }) {
    return _requestMap(
      '/v1/control-center/break-glass',
      method: 'POST',
      body: <String, Object?>{
        'organization_id': organizationId.trim(),
        'reason': reason.trim(),
        'duration_minutes': durationMinutes,
        'reauth_context_id': reauthContextId.trim(),
      },
    );
  }

  Future<void> startRecovery(String email) async {
    await _request(
      '/v1/control-center/auth/recovery/start',
      method: 'POST',
      body: <String, Object?>{'email': email.trim()},
      csrf: false,
    );
  }

  Future<void> completeRecovery({
    required String challengeId,
    required String recoverySecret,
    required String recoveryCode,
    required String newPassword,
  }) async {
    await _request(
      '/v1/control-center/auth/recovery/complete',
      method: 'POST',
      body: <String, Object?>{
        'challenge_id': challengeId.trim(),
        'recovery_secret': recoverySecret,
        'recovery_code': recoveryCode.trim(),
        'new_password': newPassword,
      },
      csrf: false,
    );
    clearInMemorySession();
  }

  Future<YallaAdminEnrollmentStart> startEnrollment({
    required String email,
    required String enrollmentSecret,
  }) async {
    final payload = await _requestMap(
      '/v1/control-center/auth/enrollment/start',
      method: 'POST',
      body: <String, Object?>{
        'email': email.trim(),
        'enrollment_secret': enrollmentSecret,
      },
      csrf: false,
    );

    final challengeId = payload['challenge_id']?.toString().trim() ?? '';
    if (challengeId.isEmpty) {
      throw const YallaAdminAuthException(
        'Server did not return an enrollment challenge.',
      );
    }

    return YallaAdminEnrollmentStart(
      challengeId: challengeId,
      totpProvisioningUri: payload['totp_provisioning_uri']?.toString(),
    );
  }

  Future<void> completeEnrollment({
    required String challengeId,
    required String newPassword,
    required String totpCode,
  }) async {
    await _request(
      '/v1/control-center/auth/enrollment/complete',
      method: 'POST',
      body: <String, Object?>{
        'challenge_id': challengeId.trim(),
        'new_password': newPassword,
        'mfa_method': 'TOTP',
        'mfa_proof': <String, Object?>{'code': totpCode.trim()},
      },
      csrf: false,
    );
    clearInMemorySession();
  }

  /// Starts the server-authoritative customer phone verification ceremony.
  /// The OTP is generated and verified by the licensing server. The client
  /// never receives the OTP in an API response and never persists it.
  Future<CustomerPhoneOtpChallenge> startCustomerPhoneVerification({
    required String phone,
  }) async {
    final payload = await _requestMap(
      '/v1/customer-phone-verification/start',
      method: 'POST',
      body: <String, Object?>{'phone': phone.trim()},
      csrf: false,
    );
    final challengeId = payload['challenge_id']?.toString().trim() ?? '';
    if (challengeId.isEmpty) {
      throw const YallaAdminAuthException(
        'Phone verification server did not return a challenge.',
      );
    }
    return CustomerPhoneOtpChallenge(
      challengeId: challengeId,
      expiresInSeconds:
          int.tryParse('${payload['expires_in_seconds'] ?? ''}') ?? 300,
      resendAfterSeconds:
          int.tryParse('${payload['resend_after_seconds'] ?? ''}') ?? 60,
      delivery: payload['delivery']?.toString() ?? 'SMS',
    );
  }

  /// Verifies the SMS code and returns a short-lived, in-memory-only token.
  /// The token is consumed before First Owner setup can continue.
  Future<CustomerPhoneVerification> verifyCustomerPhoneOtp({
    required String challengeId,
    required String code,
  }) async {
    final payload = await _requestMap(
      '/v1/customer-phone-verification/verify',
      method: 'POST',
      body: <String, Object?>{
        'challenge_id': challengeId.trim(),
        'code': code.trim(),
      },
      csrf: false,
    );
    final token = payload['verification_token']?.toString().trim() ?? '';
    final phone = payload['phone']?.toString().trim() ?? '';
    if (token.isEmpty || phone.isEmpty) {
      throw const YallaAdminAuthException(
        'Phone verification server returned an incomplete result.',
      );
    }
    return CustomerPhoneVerification(
      challengeId: challengeId.trim(),
      phone: phone,
      verificationToken: token,
    );
  }

  /// Consumes the short-lived server verification token exactly once.
  Future<void> consumeCustomerPhoneVerification({
    required String challengeId,
    required String phone,
    required String verificationToken,
  }) async {
    final payload = await _requestMap(
      '/v1/customer-phone-verification/consume',
      method: 'POST',
      body: <String, Object?>{
        'challenge_id': challengeId.trim(),
        'phone': phone.trim(),
        'verification_token': verificationToken.trim(),
      },
      csrf: false,
    );
    if (payload['status']?.toString().toUpperCase() != 'CONSUMED') {
      throw const YallaAdminAuthException(
        'Phone verification token was not consumed by the server.',
      );
    }
  }

  /// Public commercial onboarding request. This does not authenticate a Yalla
  /// administrator and does not create an organization or license by itself.
  /// The request remains PENDING until reviewed in Yalla Control Center.
  Future<Map<String, Object?>> requestCustomerOnboarding({
    required String organizationName,
    required String ownerName,
    required String ownerEmail,
    String? phone,
    String? countryCode,
  }) {
    return _requestMap(
      '/v1/customer-onboarding/request',
      method: 'POST',
      body: <String, Object?>{
        'organization_name': organizationName.trim(),
        'owner_name': ownerName.trim(),
        'owner_email': ownerEmail.trim().toLowerCase(),
        'phone': _nullIfEmpty(phone),
        'country_code': _nullIfEmpty(countryCode)?.toUpperCase(),
      },
      csrf: false,
    );
  }

  /// Super Owner assisted onboarding. The returned activation code is
  /// intentionally one-time display material; the server stores only its
  /// verifier/digest in production.
  Future<Map<String, Object?>> createCustomerOrganization({
    required String organizationName,
    required String ownerEmail,
    required String countryCode,
    required String planCode,
    required int maxUsers,
    required int maxDevices,
    int trialDays = 0,
  }) {
    return _requestMap(
      '/v1/control-center/customer-onboarding/create',
      method: 'POST',
      body: <String, Object?>{
        'organization_name': organizationName.trim(),
        'owner_email': ownerEmail.trim().toLowerCase(),
        'country_code': countryCode.trim().toUpperCase(),
        'plan_code': planCode.trim(),
        'max_users': maxUsers,
        'max_devices': maxDevices,
        'trial_days': trialDays,
      },
    );
  }

  Future<Map<String, Object?>> approveCustomerOnboarding(String requestId) {
    return _requestMap(
      '/v1/control-center/customer-onboarding/approve',
      method: 'POST',
      body: <String, Object?>{'request_id': requestId.trim()},
    );
  }

  Future<Map<String, Object?>> rejectCustomerOnboarding({
    required String requestId,
    required String reason,
  }) {
    return _requestMap(
      '/v1/control-center/customer-onboarding/reject',
      method: 'POST',
      body: <String, Object?>{
        'request_id': requestId.trim(),
        'reason': reason.trim(),
      },
    );
  }

  Future<void> logout() async {
    try {
      if (_sessionCookies.isNotEmpty) {
        await _request(
          '/v1/control-center/auth/logout',
          method: 'POST',
          body: const <String, Object?>{'reason': 'USER_LOGOUT'},
        );
      }
    } catch (_) {
      // Local cleanup is authoritative for the native process even if the
      // network is unavailable. Server expiry/revocation remains bounded.
    } finally {
      clearInMemorySession();
    }
  }

  void clearInMemorySession() {
    _sessionCookies.clear();
    _csrfToken = '';
    _identity = null;
  }

  Future<Object?> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    bool csrf = true,
  }) async {
    final base = _baseUri;
    if (base == null) {
      throw const YallaAdminAuthException(
        'Yalla Licensing Server is not configured in this build.',
      );
    }
    _assertSecureBaseUri(base);

    final uri = base.resolve(path);
    try {
      final HttpClientRequest request;
      switch (method.toUpperCase()) {
        case 'POST':
          request = await _httpClient.postUrl(uri).timeout(timeout);
          break;
        case 'GET':
          request = await _httpClient.getUrl(uri).timeout(timeout);
          break;
        default:
          throw YallaAdminAuthException('Unsupported HTTP method: $method');
      }

      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('x-yalla-client', 'yalla-accounts-desktop-unified');
      if (_sessionCookies.isNotEmpty) {
        request.headers.set(
          HttpHeaders.cookieHeader,
          _sessionCookies.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; '),
        );
      }
      if (csrf && method.toUpperCase() != 'GET' && _csrfToken.isNotEmpty) {
        request.headers.set('X-Yalla-CSRF', _csrfToken);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(timeout);
      _captureCookies(response);
      final raw = await utf8.decoder.bind(response).join().timeout(timeout);

      Object? decoded;
      try {
        decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
      } catch (_) {
        throw YallaAdminAuthException(
          'Yalla server returned invalid JSON.',
          statusCode: response.statusCode,
        );
      }

      final payload = decoded is Map
          ? decoded.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            )
          : decoded;
      if (payload is Map<String, Object?>) {
        final csrfToken = payload['csrf_token']?.toString().trim();
        if (csrfToken != null && csrfToken.isNotEmpty) {
          _csrfToken = csrfToken;
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = payload is Map<String, Object?>
            ? payload['message']?.toString().trim()
            : null;
        throw YallaAdminAuthException(
          message?.isNotEmpty == true
              ? message!
              : 'Yalla administrative request was rejected.',
          statusCode: response.statusCode,
        );
      }

      return payload;
    } on YallaAdminAuthException {
      rethrow;
    } on TimeoutException {
      throw const YallaAdminAuthException('Yalla server timed out.');
    } on SocketException {
      throw const YallaAdminAuthException(
        'Internet connection or Yalla server is unavailable.',
      );
    } on HandshakeException {
      throw const YallaAdminAuthException(
        'Secure connection to Yalla server failed.',
      );
    }
  }

  Future<Map<String, Object?>> _requestMap(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    bool csrf = true,
  }) async {
    return _requireMap(
      await _request(path, method: method, body: body, csrf: csrf),
    );
  }

  static Map<String, Object?> _requireMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map<String, Object?>(
        (key, item) => MapEntry(key.toString(), item),
      );
    }
    throw const YallaAdminAuthException(
      'Yalla server returned an invalid object response.',
    );
  }

  void _captureCookies(HttpClientResponse response) {
    final values = response.headers[HttpHeaders.setCookieHeader];
    if (values == null) return;

    for (final header in values) {
      final pair = header.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      final lower = header.toLowerCase();
      final expiresNow = lower.contains('max-age=0') || value.isEmpty;
      if (expiresNow) {
        _sessionCookies.remove(name);
      } else {
        _sessionCookies[name] = value;
      }
    }
  }

  void _assertSecureBaseUri(Uri uri) {
    if (uri.scheme == 'https' && uri.host.isNotEmpty) return;
    final loopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (allowInsecureLoopbackForTesting && uri.scheme == 'http' && loopback) {
      return;
    }
    throw const YallaAdminAuthException(
      'Yalla server URL must use HTTPS.',
    );
  }

  static String _normalizedEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) return '/dashboard';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  static String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) return <String, Object?>{};
    return value.map<String, Object?>(
      (key, item) => MapEntry(key.toString(), item),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
