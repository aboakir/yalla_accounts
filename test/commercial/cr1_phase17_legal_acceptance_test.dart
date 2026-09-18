import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/legal/legal_acceptance_service.dart';
import 'package:yalla_accounts/core/legal/local_legal_documents.dart';
import 'package:yalla_accounts/core/legal/support_complaint_service.dart';

void main() {
  test(
    'Phase 17 legal acceptance sends explicit current versions and source',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final handled = server.first.then((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/legal/acceptance');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer ${'a' * 40}',
        );
        expect(request.headers.value('x-yalla-contract-version'), '2');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['terms_version'], 'terms_ps_v1');
        expect(body['privacy_version'], 'privacy_ps_v1');
        expect(body['terms_accepted'], isTrue);
        expect(body['privacy_accepted'], isTrue);
        expect(body['acceptance_source'], 'SIGNUP');

        request.response.statusCode = 201;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'acceptance_id': '11111111-1111-4111-8111-111111111111',
            'terms_version': 'terms_ps_v1',
            'privacy_version': 'privacy_ps_v1',
            'accepted_at': '2026-09-18T10:00:00Z',
            'acceptance_source': 'SIGNUP',
          }),
        );
        await request.response.close();
      });

      final service = HttpLegalAcceptanceService(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        bearerTokenProvider: () async => 'a' * 40,
        allowInsecureLoopbackForTesting: true,
      );
      addTearDown(service.dispose);
      final result = await service.accept(source: 'SIGNUP');
      await handled;
      expect(result.acceptanceId, '11111111-1111-4111-8111-111111111111');
      expect(result.termsVersion, 'terms_ps_v1');
      expect(result.privacyVersion, 'privacy_ps_v1');
    },
  );

  test('Phase 17 consent UI starts unchecked and exposes legal links', () {
    final source = File(
      'lib/features/cloud_auth/cloud_auth_screen.dart',
    ).readAsStringSync();
    expect(source, contains('bool _termsAccepted = false;'));
    expect(source, contains('bool _privacyAccepted = false;'));
    expect(source, contains("Key('termsAcceptanceCheckbox')"));
    expect(source, contains("Key('privacyAcceptanceCheckbox')"));
    expect(source, contains('ReleaseLegalLinks(compact: true)'));
    expect(
      source,
      contains('يجب الموافقة صراحة على شروط الاستخدام وسياسة الخصوصية'),
    );
  });

  test(
    'Phase 17 legal acceptance fails closed without verified token',
    () async {
      final service = HttpLegalAcceptanceService(
        baseUri: Uri.parse('https://control.example.invalid'),
        bearerTokenProvider: () async => null,
      );
      addTearDown(service.dispose);
      await expectLater(
        service.accept(source: 'ONBOARDING'),
        throwsA(
          isA<LegalAcceptanceException>().having(
            (error) => error.userMessage,
            'userMessage',
            contains('تسجيل دخول سحابي موثّق'),
          ),
        ),
      );
    },
  );

  test('Phase 17 canonical legal v1 documents are bundled and hash-locked', () {
    for (final document in LocalLegalDocuments.all) {
      final file = File(document.assetPath);
      expect(file.existsSync(), isTrue, reason: document.assetPath);
      final bytes = file.readAsBytesSync();
      expect(
        sha256.convert(bytes).toString(),
        document.sha256,
        reason: document.version,
      );
      final text = utf8.decode(bytes);
      expect(text, isNot(contains('DRAFT')));
      expect(text, isNot(contains('TODO')));
      expect(text, isNot(contains('{{SUPPORT_EMAIL}}')));
      expect(text, contains('yalla.accou@gmail.com'));
    }
  });

  test('Phase 17 complaint submission returns durable complaint id', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/support/complaints');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer ${'b' * 40}',
      );
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['category'], 'TECHNICAL');
      expect(body['message'], contains('synchronization'));
      request.response.statusCode = 201;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'complaint_id': '22222222-2222-4222-8222-222222222222',
          'status': 'OPEN',
        }),
      );
      await request.response.close();
    });
    final service = HttpSupportComplaintService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      bearerTokenProvider: () async => 'b' * 40,
      allowInsecureLoopbackForTesting: true,
    );
    addTearDown(service.dispose);
    final result = await service.submit(
      category: 'TECHNICAL',
      message: 'A synchronization issue requires support review.',
    );
    await handled;
    expect(result.complaintId, '22222222-2222-4222-8222-222222222222');
    expect(result.status, 'OPEN');
  });
}
