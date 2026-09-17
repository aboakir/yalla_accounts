import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/privacy/account_deletion_request_service.dart';

void main() {
  test('Phase 17 deletion request uses verified bearer and Control contract',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/privacy/deletion-request');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer ${'a' * 40}');
      expect(request.headers.value('x-yalla-contract-version'), '2');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body, {'confirm_delete_account': true});
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'request_id': '11111111-1111-4111-8111-111111111111',
        'status': 'PENDING',
      }));
      await request.response.close();
    });
    final service = HttpAccountDeletionRequestService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      bearerTokenProvider: () async => 'a' * 40,
      allowInsecureLoopbackForTesting: true,
    );
    addTearDown(service.dispose);
    final result = await service.requestDeletion();
    await handled;
    expect(result.requestId, '11111111-1111-4111-8111-111111111111');
    expect(result.status, 'PENDING');
  });

  test('Phase 17 deletion request fails closed without verified cloud token',
      () async {
    final service = HttpAccountDeletionRequestService(
      baseUri: Uri.parse('https://control.example.invalid'),
      bearerTokenProvider: () async => null,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.requestDeletion(),
      throwsA(
        isA<AccountDeletionRequestException>().having(
          (error) => error.userMessage,
          'userMessage',
          contains('تسجيل دخول سحابي موثّق'),
        ),
      ),
    );
  });

  test(
      'Phase 17 production deletion endpoint rejects insecure non-loopback base',
      () async {
    final service = HttpAccountDeletionRequestService(
      baseUri: Uri.parse('http://example.invalid'),
      bearerTokenProvider: () async => 'a' * 40,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.requestDeletion(),
      throwsA(isA<AccountDeletionRequestException>()),
    );
  });
}
