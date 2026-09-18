import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LegalAcceptanceException implements Exception {
  const LegalAcceptanceException(this.userMessage, {this.requestId});
  final String userMessage;
  final String? requestId;
  @override
  String toString() =>
      requestId == null ? userMessage : '$userMessage (request: $requestId)';
}

class LegalAcceptanceResult {
  const LegalAcceptanceResult({
    required this.acceptanceId,
    required this.termsVersion,
    required this.privacyVersion,
  });
  final String acceptanceId;
  final String termsVersion;
  final String privacyVersion;
}

class HttpLegalAcceptanceService {
  HttpLegalAcceptanceService({
    Uri? baseUri,
    required this.bearerTokenProvider,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.allowInsecureLoopbackForTesting = false,
  })  : baseUri = baseUri ?? configuredBaseUri,
        _httpClient = httpClient ?? HttpClient();

  static const termsVersion = 'terms_ps_v1';
  static const privacyVersion = 'privacy_ps_v1';
  final Uri? baseUri;
  final Future<String?> Function() bearerTokenProvider;
  final HttpClient _httpClient;
  final Duration timeout;
  final bool allowInsecureLoopbackForTesting;

  static Uri? get configuredBaseUri {
    const raw = String.fromEnvironment('YALLA_LICENSING_BASE_URL');
    final value = raw.trim();
    return value.isEmpty ? null : Uri.tryParse(value);
  }

  Future<LegalAcceptanceResult> accept({required String source}) async {
    final normalizedSource = source.trim().toUpperCase();
    if (!const {
      'SIGNUP',
      'ONBOARDING',
      'ACCOUNT_SETTINGS',
    }.contains(normalizedSource)) {
      throw const LegalAcceptanceException('مصدر الموافقة القانونية غير صالح.');
    }
    final base = baseUri;
    if (base == null) {
      throw const LegalAcceptanceException(
        'خدمة توثيق الموافقة القانونية غير مهيأة في هذا الإصدار.',
      );
    }
    _validateBase(base);
    final token = await bearerTokenProvider().timeout(timeout);
    if (token == null ||
        !RegExp(r'^[A-Za-z0-9._~-]{32,4096}$').hasMatch(token)) {
      throw const LegalAcceptanceException(
        'يلزم تسجيل دخول سحابي موثّق قبل حفظ الموافقة.',
      );
    }
    final uri = base.resolve('/v1/legal/acceptance');
    try {
      final request = await _httpClient.postUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set('x-yalla-contract-version', '2');
      request.headers.set('x-yalla-client', 'yallah-accounts');
      request.write(
        jsonEncode({
          'terms_version': termsVersion,
          'privacy_version': privacyVersion,
          'terms_accepted': true,
          'privacy_accepted': true,
          'acceptance_source': normalizedSource,
        }),
      );
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      Map<String, Object?> body = const {};
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          body = decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {}
      final requestId = response.headers.value('x-request-id')?.trim();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LegalAcceptanceException(
          response.statusCode == 409
              ? 'تم تحديث الوثائق القانونية. افتح الشروط والخصوصية ووافق على النسخة الحالية.'
              : response.statusCode == 401
                  ? 'انتهت جلسة الحساب السحابي. سجّل الدخول ثم أعد المحاولة.'
                  : 'تعذر حفظ الموافقة القانونية على خادم Yallah.',
          requestId: requestId,
        );
      }
      final acceptanceId = body['acceptance_id']?.toString().trim() ?? '';
      final returnedTerms = body['terms_version']?.toString().trim() ?? '';
      final returnedPrivacy = body['privacy_version']?.toString().trim() ?? '';
      if (acceptanceId.isEmpty ||
          returnedTerms != termsVersion ||
          returnedPrivacy != privacyVersion) {
        throw LegalAcceptanceException(
          'أعاد خادم Yallah دليلاً قانونياً غير مكتمل.',
          requestId: requestId,
        );
      }
      return LegalAcceptanceResult(
        acceptanceId: acceptanceId,
        termsVersion: returnedTerms,
        privacyVersion: returnedPrivacy,
      );
    } on LegalAcceptanceException {
      rethrow;
    } on TimeoutException {
      throw const LegalAcceptanceException(
        'انتهت مهلة الاتصال أثناء حفظ الموافقة القانونية.',
      );
    } catch (_) {
      throw const LegalAcceptanceException(
        'تعذر الاتصال بخادم Yallah لحفظ الموافقة القانونية.',
      );
    }
  }

  void _validateBase(Uri uri) {
    if (uri.scheme == 'https' && uri.host.isNotEmpty) return;
    final loopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (allowInsecureLoopbackForTesting && uri.scheme == 'http' && loopback) {
      return;
    }
    throw const LegalAcceptanceException(
      'عنوان خادم Yallah غير آمن أو غير صالح.',
    );
  }

  void dispose() => _httpClient.close(force: true);
}
