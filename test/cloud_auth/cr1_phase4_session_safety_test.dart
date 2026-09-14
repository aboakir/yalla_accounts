import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_secure_storage.dart';
import 'package:yalla_accounts/features/cloud_auth/supabase_identity_provider.dart';
import 'package:yalla_accounts/features/onboarding/customer_onboarding_client.dart';
import 'cr1_phase3_identity_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'failed remote logout still revokes local tokens and restart cannot resurrect saved session',
      () async {
    final jwt =
        fixture.token(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
    var networkCalls = 0;
    SupabaseClient sdk() =>
        SupabaseClient(fixture.config.url, fixture.config.publicKey,
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient((request) async {
          networkCalls++;
          if (request.url.path.endsWith('/logout')) {
            throw StateError('isolated offline logout');
          }
          return http.Response(jsonEncode(fixture.user()), 200);
        }));
    final cloud = sdk();
    addTearDown(cloud.dispose);
    await cloud.auth.setInitialSession(jsonEncode(fixture.session(jwt)));
    final identity = SupabaseIdentityProvider(fixture.config, client: cloud);
    addTearDown(identity.dispose);
    expect((await identity.verifiedOnboardingSession()).authUserId,
        fixture.userId);
    await expectLater(identity.signOut(), throwsA(anything));
    expect(await identity.verifiedAccessToken(), null);
    final storage = CloudSecureStorage(
        sha256.convert(utf8.encode(fixture.config.issuer)).toString());
    expect(await storage.isSignedOut(), true);
    expect(await storage.accessToken(), null);
    final restored = sdk();
    addTearDown(restored.dispose);
    await restored.auth.setInitialSession(jsonEncode(fixture.session(jwt)));
    final restart = SupabaseIdentityProvider(fixture.config, client: restored);
    addTearDown(restart.dispose);
    final before = networkCalls;
    expect(await restart.verifiedAccessToken(), null);
    expect(networkCalls, before);
  });
  test(
      'onboarding response parser never accepts unknown status, injected authority, malformed approval or extra secret fields',
      () {
    final pending = <String, Object?>{
      'contract_version': 2,
      'request_id': fixture.userId,
      'status': 'PENDING',
      'server_time': '2026-09-15T00:00:00Z',
      'submitted_at': '2026-09-15T00:00:00Z',
      'reviewed_at': null,
      'rejection_reason': null
    };
    expect(CustomerOnboardingStatus.parse(pending).operationalAccess, false);
    for (final change in [
      {'status': 'UNKNOWN'},
      {'status': 'APPROVED'},
      {'customer_id': fixture.userId},
      {'activation_code': 'not-customer-material'},
      {'admin_data': {}},
      {'contract_version': 1},
      {'server_time': 'bad'}
    ]) {
      expect(() => CustomerOnboardingStatus.parse({...pending, ...change}),
          throwsA(isA<CustomerOnboardingException>()));
    }
  });
  test(
      'customer onboarding refuses HTTP without explicit loopback test permission',
      () async {
    final client = CustomerOnboardingClient(
        baseUri: Uri.parse('http://127.0.0.1:1'),
        sessionProvider: () async =>
            const VerifiedOnboardingSession(fixture.userId, 'unused'));
    addTearDown(client.close);
    await expectLater(
        client.send(const VerifiedOnboardingSession(fixture.userId, 'unused'),
            'status', {}),
        throwsA(isA<CustomerOnboardingException>()));
  });
}
