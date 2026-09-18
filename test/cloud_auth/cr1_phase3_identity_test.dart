import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_config.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';
import 'package:yalla_accounts/features/cloud_auth/supabase_identity_provider.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_secure_storage.dart';
import 'package:yalla_accounts/core/licensing/commercial_licensing_providers.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_transport.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_lifecycle_transport.dart';
import 'package:crypto/crypto.dart';

const config = CloudAuthConfig(
    url: 'https://identity.example.invalid',
    publicKey: 'sb_publishable_isolated_fixture_only',
    releaseReady: true);
const userId = '11111111-1111-4111-8111-111111111111';
String token(int expiry, {String subject = userId}) =>
    '${base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '')}.'
    '${base64Url.encode(utf8.encode(jsonEncode({
              'sub': subject,
              'exp': expiry,
              'amr': [
                {'method': 'password'}
              ]
            }))).replaceAll('=', '')}.fixture_signature';
Map<String, dynamic> user([String id = userId]) => {
      'id': id,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'same@example.invalid',
      'email_confirmed_at': '2026-01-01T00:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {'customer_id': 'forged'}
    };
Map<String, dynamic> session(String jwt) => {
      'access_token': jwt,
      'refresh_token': 'fixture_refresh_only',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user()
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'licensing validates persisted token with getUser and Riverpod shares the real provider',
      () async {
    final jwt = token(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
    var requests = 0;
    final client = SupabaseClient(config.url, config.publicKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requests++;
      expect(request.url.path, '/auth/v1/user');
      expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          'Bearer $jwt');
      return http.Response(jsonEncode(user()), 200);
    }));
    addTearDown(client.dispose);
    await client.auth.setInitialSession(jsonEncode(session(jwt)));
    final identity = SupabaseIdentityProvider(config, client: client);
    addTearDown(identity.dispose);
    final container = ProviderContainer(
        overrides: [supabaseIdentityProvider.overrideWithValue(identity)]);
    addTearDown(container.dispose);
    final activation =
        container.read(activationTransportProvider) as HttpActivationTransport;
    final lifecycle = container.read(licenseLifecycleTransportProvider)
        as HttpLicenseLifecycleTransport;
    expect(await activation.bearerTokenProvider!(), jwt);
    expect(await lifecycle.bearerTokenProvider!(), jwt);
    expect(requests, 2);
    expect(container.read(activationServiceProvider), isNotNull);
    expect(container.read(licenseLifecycleServiceProvider), isNotNull);
  });
  test('expired session refreshes then network-validates the replacement token',
      () async {
    final expired = token(1),
        fresh = token(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
    var refresh = 0, verified = 0;
    final client = SupabaseClient(config.url, config.publicKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/token')) {
        refresh++;
        return http.Response(jsonEncode(session(fresh)), 200);
      }
      verified++;
      expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          'Bearer $fresh');
      return http.Response(jsonEncode(user()), 200);
    }));
    addTearDown(client.dispose);
    await client.auth.setInitialSession(jsonEncode(session(expired)));
    final identity = SupabaseIdentityProvider(config, client: client);
    addTearDown(identity.dispose);
    expect(await identity.verifiedAccessToken(), fresh);
    expect(refresh, 1);
    expect(verified, 1);
  });
  test(
      'missing, forged, unavailable, wrong user and recovery sessions never supply a token',
      () async {
    final jwt = token(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
    var mode = 'reject', requests = 0;
    final client = SupabaseClient(config.url, config.publicKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requests++;
      if (mode == 'offline') throw StateError('private provider failure');
      if (mode == 'wrong') {
        return http.Response(
            jsonEncode(user('22222222-2222-4222-8222-222222222222')), 200);
      }
      return http.Response('{"message":"invalid"}', 401);
    }));
    addTearDown(client.dispose);
    final identity = SupabaseIdentityProvider(config, client: client);
    addTearDown(identity.dispose);
    expect(await identity.verifiedAccessToken(), null);
    expect(requests, 0);
    for (final value in ['reject', 'offline', 'wrong']) {
      await client.auth.setInitialSession(jsonEncode(session(jwt)));
      mode = value;
      expect(await identity.verifiedAccessToken(), null);
    }
    identity.recoveryPending = true;
    final before = requests;
    expect(await identity.verifiedAccessToken(), null);
    expect(requests, before);
  });
  test(
      'recovery deny state survives provider recreation and rejects cached valid session',
      () async {
    final jwt = token(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
    final storage = CloudSecureStorage(
        sha256.convert(utf8.encode(config.issuer)).toString());
    await storage.setRecoveryPending(true);
    var requests = 0;
    final client = SupabaseClient(config.url, config.publicKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((_) async {
      requests++;
      return http.Response(jsonEncode(user()), 200);
    }));
    addTearDown(client.dispose);
    await client.auth.setInitialSession(jsonEncode(session(jwt)));
    final identity = SupabaseIdentityProvider(config, client: client);
    addTearDown(identity.dispose);
    expect(await identity.verifiedAccessToken(), null);
    expect(identity.recoveryPending, true);
    expect(requests, 0);
  });
}
