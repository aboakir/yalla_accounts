import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_client.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_models.dart';

void main() {
  test(
    'registration posts the PHP contract and parses pending state',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'request_id': 'req',
            'data': {
              'customer_id': 'c-1',
              'customer_code': '+970599000000',
              'customer_status': 'PENDING',
              'device_request_status': 'PENDING',
            },
          }),
          200,
        );
      });
      final api = CommercialBackendClient(
        baseUri: Uri.parse('http://127.0.0.1:8080/yallah_backend/'),
        httpClient: client,
        allowInsecureLoopbackForTesting: true,
      );
      final result = await api.register(
        payload: {
          'business_name': 'Garage',
          'owner_name': 'Owner',
          'phone_e164': '+970599000000',
          'country_code': 'PS',
          'installation_id': '11111111-1111-4111-8111-111111111111',
          'registration_request_id': '22222222-2222-4222-8222-222222222222',
          'activation_secret': 'A' * 43,
          'platform': 'windows',
          'device_name': 'PC',
          'app_version': '1.0.3+22',
        },
      );

      expect(captured.url.path, '/yallah_backend/api/v1/register.php');
      expect(captured.method, 'POST');
      expect(result.isPending, isTrue);
      expect(result.customerCode, '+970599000000');
    },
  );

  test('license check parses access mode and signed lease', () async {
    final api = CommercialBackendClient(
      baseUri: Uri.parse('https://yallah.example/'),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'server_time': '2026-09-25T10:00:00Z',
            'data': {
              'customer_id': 'c1',
              'customer_code': '+970599000000',
              'access_mode': 'READ_ONLY',
              'subscription_status': 'EXPIRED',
              'device_id': 'd1',
              'lease_until': '2026-09-25T12:00:00Z',
              'lease_token': 'signed-token',
            },
          }),
          200,
        ),
      ),
    );
    final result = await api.licenseCheck(
      installationId: '11111111-1111-4111-8111-111111111111',
      deviceToken: 'token',
    );

    expect(result.isReadOnly, isTrue);
    expect(result.subscriptionStatus, 'EXPIRED');
    expect(result.leaseToken, 'signed-token');
  });

  test('backend errors preserve stable code and request id', () async {
    final api = CommercialBackendClient(
      baseUri: Uri.parse('https://yallah.example/'),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': false,
            'request_id': 'support-123',
            'error': {
              'code': 'DEVICE_NOT_AUTHORIZED',
              'message': 'Device is not authorized.',
            },
          }),
          403,
        ),
      ),
    );

    await expectLater(
      api.licenseCheck(
        installationId: '11111111-1111-4111-8111-111111111111',
        deviceToken: 'bad-token',
      ),
      throwsA(
        isA<CommercialBackendException>()
            .having((e) => e.code, 'code', 'DEVICE_NOT_AUTHORIZED')
            .having((e) => e.requestId, 'requestId', 'support-123'),
      ),
    );
  });
}
