import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SupportComplaintException implements Exception {
  const SupportComplaintException(this.userMessage, {this.requestId});
  final String userMessage;
  final String? requestId;

  @override
  String toString() =>
      requestId == null ? userMessage : '$userMessage (request: $requestId)';
}

class SupportComplaintResult {
  const SupportComplaintResult({
    required this.complaintId,
    required this.status,
  });

  final String complaintId;
  final String status;
}

class HttpSupportComplaintService {
  HttpSupportComplaintService({
    Uri? baseUri,
    required this.bearerTokenProvider,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.allowInsecureLoopbackForTesting = false,
  })  : baseUri = baseUri ?? configuredBaseUri,
        _httpClient = httpClient ?? HttpClient();

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

  Future<SupportComplaintResult> submit({
    required String category,
    required String message,
  }) async {
    final normalizedCategory = category.trim().toUpperCase();
    if (!const {
      'ACCOUNT',
      'SUBSCRIPTION',
      'PAYMENT',
      'TECHNICAL',
      'PRIVACY',
      'SECURITY',
      'COMMERCIAL',
      'OTHER',
    }.contains(normalizedCategory)) {
      throw const SupportComplaintException('نوع الشكوى غير صالح.');
    }
    final text = message.trim();
    if (text.length < 10 || text.length > 4000) {
      throw const SupportComplaintException(
        'اكتب وصفًا واضحًا للشكوى بين 10 و4000 حرف.',
      );
    }
    final base = baseUri;
    if (base == null) {
      throw const SupportComplaintException(
        'خدمة الشكاوى غير مهيأة في هذا الإصدار.',
      );
    }
    _validateBase(base);
    final token = await bearerTokenProvider().timeout(timeout);
    if (token == null ||
        !RegExp(r'^[A-Za-z0-9._~-]{32,4096}$').hasMatch(token)) {
      throw const SupportComplaintException(
        'يلزم تسجيل دخول سحابي موثّق قبل إرسال الشكوى.',
      );
    }

    try {
      final request = await _httpClient
          .postUrl(base.resolve('/v1/support/complaints'))
          .timeout(timeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set('x-yalla-contract-version', '2');
      request.headers.set('x-yalla-client', 'yallah-accounts');
      request.write(
        jsonEncode({'category': normalizedCategory, 'message': text}),
      );

      final response = await request.close().timeout(timeout);
      final responseText =
          await utf8.decoder.bind(response).join().timeout(timeout);
      Map<String, Object?> body = const {};
      try {
        final decoded = jsonDecode(responseText);
        if (decoded is Map) {
          body = decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {}

      final requestId = response.headers.value('x-request-id')?.trim();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SupportComplaintException(
          response.statusCode == 401
              ? 'انتهت جلسة الحساب السحابي. سجّل الدخول ثم أعد المحاولة.'
              : 'تعذر إرسال الشكوى إلى خادم Yallah.',
          requestId: requestId,
        );
      }

      final complaintId = body['complaint_id']?.toString().trim() ?? '';
      final status = body['status']?.toString().trim().toUpperCase() ?? '';
      if (complaintId.isEmpty || status.isEmpty) {
        throw SupportComplaintException(
          'أعاد خادم Yallah مرجع شكوى غير مكتمل.',
          requestId: requestId,
        );
      }
      return SupportComplaintResult(
        complaintId: complaintId,
        status: status,
      );
    } on SupportComplaintException {
      rethrow;
    } on TimeoutException {
      throw const SupportComplaintException(
        'انتهت مهلة الاتصال أثناء إرسال الشكوى.',
      );
    } catch (_) {
      throw const SupportComplaintException(
        'تعذر الاتصال بخادم Yallah لإرسال الشكوى.',
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
    throw const SupportComplaintException(
      'عنوان خادم Yallah غير آمن أو غير صالح.',
    );
  }

  void dispose() => _httpClient.close(force: true);
}
