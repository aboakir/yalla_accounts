import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AccountDeletionRequestException implements Exception {
  const AccountDeletionRequestException(
    this.userMessage, {
    this.supportRequestId,
  });
  final String userMessage;
  final String? supportRequestId;
  @override
  String toString() => supportRequestId == null
      ? userMessage
      : '$userMessage (request: $supportRequestId)';
}

class AccountDeletionRequestResult {
  const AccountDeletionRequestResult({
    required this.requestId,
    required this.status,
  });
  final String requestId;
  final String status;
}

typedef AccountDeletionBearerTokenProvider = Future<String?> Function();

class HttpAccountDeletionRequestService {
  HttpAccountDeletionRequestService({
    Uri? baseUri,
    required this.bearerTokenProvider,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.allowInsecureLoopbackForTesting = false,
  })  : baseUri = baseUri ?? configuredBaseUri,
        _httpClient = httpClient ?? HttpClient();
  final Uri? baseUri;
  final AccountDeletionBearerTokenProvider bearerTokenProvider;
  final HttpClient _httpClient;
  final Duration timeout;
  final bool allowInsecureLoopbackForTesting;

  static Uri? get configuredBaseUri {
    const raw = String.fromEnvironment('YALLA_LICENSING_BASE_URL');
    final value = raw.trim();
    return value.isEmpty ? null : Uri.tryParse(value);
  }

  Future<AccountDeletionRequestResult> requestDeletion() async {
    final base = baseUri;
    if (base == null) {
      throw const AccountDeletionRequestException(
        'خدمة طلب حذف الحساب غير مهيأة في هذا الإصدار.',
      );
    }
    _validateBase(base);
    final token = await bearerTokenProvider().timeout(timeout);
    if (token == null ||
        !RegExp(r'^[A-Za-z0-9._~-]{32,4096}$').hasMatch(token)) {
      throw const AccountDeletionRequestException(
        'يلزم تسجيل دخول سحابي موثّق قبل إرسال طلب الحذف.',
      );
    }
    final uri = base.resolve('/v1/privacy/deletion-request');
    HttpClientRequest? request;
    try {
      request = await _httpClient.postUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set('x-yalla-contract-version', '2');
      request.headers.set('x-yalla-client', 'yalla-accounts');
      request.write(jsonEncode(const {'confirm_delete_account': true}));
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      Map<String, Object?> payload = const {};
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          payload = decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {}
      final requestId = payload['request_id']?.toString().trim();
      final supportId = requestId?.isNotEmpty == true
          ? requestId
          : response.headers.value('x-request-id')?.trim();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AccountDeletionRequestException(
          response.statusCode == 401
              ? 'انتهت جلسة الحساب السحابي. سجل الدخول ثم أعد المحاولة.'
              : 'تعذر إرسال طلب الحذف إلى خادم Yalla.',
          supportRequestId: supportId,
        );
      }
      final status = payload['status']?.toString().trim().toUpperCase() ?? '';
      if (requestId == null || requestId.isEmpty || status.isEmpty) {
        throw AccountDeletionRequestException(
          'أعاد خادم Yalla نتيجة حذف غير مكتملة.',
          supportRequestId: supportId,
        );
      }
      return AccountDeletionRequestResult(requestId: requestId, status: status);
    } on AccountDeletionRequestException {
      rethrow;
    } on TimeoutException {
      throw const AccountDeletionRequestException(
        'انتهت مهلة الاتصال أثناء إرسال طلب الحذف.',
      );
    } catch (_) {
      throw const AccountDeletionRequestException(
        'تعذر الاتصال بخادم Yalla لإرسال طلب الحذف.',
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
    throw const AccountDeletionRequestException(
      'عنوان خادم Yalla غير آمن أو غير صالح.',
    );
  }

  void dispose() => _httpClient.close(force: true);
}
