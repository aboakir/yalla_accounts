import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../cloud_auth/supabase_identity_provider.dart';

class CustomerOnboardingException implements Exception {
  const CustomerOnboardingException(this.code, {this.status});
  final String code;
  final int? status;
}

class CustomerOnboardingStatus {
  CustomerOnboardingStatus._(this.data);
  final Map<String, Object?> data;
  String get status => data['status']! as String;
  String get requestId => data['request_id']! as String;
  bool get approved => status == 'APPROVED';
  // Approval never opens the workshop. Signed activation remains mandatory.
  bool get operationalAccess => false;
  static CustomerOnboardingStatus parse(Map<String, Object?> data) {
    final uuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    const allowed = [
      'contract_version',
      'server_time',
      'request_id',
      'status',
      'submitted_at',
      'reviewed_at',
      'rejection_reason',
      'customer_id',
      'organization_id',
      'subscription_id',
      'plan_code',
      'trial_days',
      'started_at',
      'license_id',
      'license_status',
      'activation_id',
      'activation_status'
    ];
    if (data.keys.any((k) => !allowed.contains(k))) {
      throw const CustomerOnboardingException('UNKNOWN_RESPONSE_FIELDS');
    }
    if (data['contract_version'] != 2 ||
        !['PENDING', 'APPROVED', 'REJECTED'].contains(data['status']) ||
        !uuid.hasMatch(data['request_id']?.toString() ?? '') ||
        DateTime.tryParse(data['server_time']?.toString() ?? '') == null ||
        DateTime.tryParse(data['submitted_at']?.toString() ?? '') == null ||
        data.containsKey('activation_code')) {
      throw const CustomerOnboardingException('INVALID_SERVER_RESPONSE');
    }
    const ids = [
      'customer_id',
      'organization_id',
      'subscription_id',
      'license_id',
      'activation_id'
    ];
    if (data['status'] == 'APPROVED') {
      if (ids.any((k) => !uuid.hasMatch(data[k]?.toString() ?? '')) ||
          data['plan_code'] is! String ||
          (data['plan_code'] as String).trim().isEmpty ||
          data['trial_days'] is! int ||
          (data['trial_days'] as int) < 0 ||
          (data['trial_days'] as int) > 3650 ||
          DateTime.tryParse(data['reviewed_at']?.toString() ?? '') == null ||
          !['PENDING_ACTIVATION', 'ACTIVE', 'EXPIRED', 'REVOKED', 'REPLACED']
              .contains(data['license_status']) ||
          ![
            'ISSUED',
            'REQUESTED',
            'APPROVED',
            'REDEEMED',
            'EXPIRED',
            'REJECTED'
          ].contains(data['activation_status'])) {
        throw const CustomerOnboardingException('INVALID_SERVER_RESPONSE');
      }
    } else if (ids.any((k) => data[k] != null)) {
      throw const CustomerOnboardingException(
          'UNEXPECTED_COMMERCIAL_AUTHORITY');
    }
    return CustomerOnboardingStatus._(Map.unmodifiable(data));
  }
}

class CustomerOnboardingClient {
  CustomerOnboardingClient(
      {required this.sessionProvider,
      Uri? baseUri,
      HttpClient? httpClient,
      this.allowInsecureLoopbackForTesting = false})
      : baseUri = baseUri ??
            Uri.tryParse(
                const String.fromEnvironment('YALLA_LICENSING_BASE_URL')),
        _http = httpClient ?? HttpClient();
  final Future<VerifiedOnboardingSession> Function() sessionProvider;
  final Uri? baseUri;
  final HttpClient _http;
  final bool allowInsecureLoopbackForTesting;
  void close() => _http.close(force: true);

  Future<CustomerOnboardingStatus> send(VerifiedOnboardingSession session,
      String operation, Map<String, Object?> body) async {
    final base = baseUri;
    if (base == null ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        !['', '/'].contains(base.path) ||
        !(base.scheme == 'https' ||
            (allowInsecureLoopbackForTesting &&
                base.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(base.host)))) {
      throw const CustomerOnboardingException('ONBOARDING_NOT_CONFIGURED');
    }
    if (!['request', 'status'].contains(operation)) {
      throw const CustomerOnboardingException('INVALID_OPERATION');
    }
    try {
      return await (() async {
        final request = await _http
            .postUrl(base.resolve('/v1/accounts-onboarding/$operation'));
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set('Authorization', 'Bearer ${session.accessToken}');
        request.headers.set('X-Yalla-Contract-Version', '2');
        request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode != 200) {
          await response.drain<void>();
          throw CustomerOnboardingException('ONBOARDING_DENIED',
              status: response.statusCode);
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 65536) {
            throw const CustomerOnboardingException('RESPONSE_TOO_LARGE');
          }
        }
        return CustomerOnboardingStatus.parse(
            Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map));
      })()
          .timeout(const Duration(seconds: 12));
    } on CustomerOnboardingException {
      rethrow;
    } catch (_) {
      throw const CustomerOnboardingException('ONBOARDING_UNAVAILABLE');
    }
  }
}
