import 'package:yalla_accounts/core/legal/legal_acceptance_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/features/auth/services/first_owner_bootstrap_service.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_config.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_secure_storage.dart';
import 'package:yalla_accounts/features/cloud_auth/supabase_identity_provider.dart';
import 'package:yalla_accounts/features/onboarding/customer_onboarding_client.dart';
import 'package:yalla_accounts/features/onboarding/customer_onboarding_service.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

Future<Map<String, dynamic>> _readFixtureInfo(
  StreamIterator<String> lines,
  Set<String> requiredKeys,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final remaining = deadline.difference(DateTime.now());
    if (!await lines.moveNext().timeout(remaining)) break;
    try {
      final decoded = jsonDecode(lines.current);
      if (decoded is Map) {
        final info = Map<String, dynamic>.from(decoded);
        if (requiredKeys.every(info.containsKey)) return info;
      }
    } catch (_) {
      // Structured server logs may precede the fixture metadata line.
    }
  }
  throw StateError('Phase 4 fixture metadata was not emitted.');
}

void main() {
  _NetworkBinding();
  final controlRoot = Platform.environment['YALLA_CR1_CONTROL_ROOT'];
  test(
      'Phase 4 fresh DB signup OTP pending restart approval canonical owner staging; no activation bypass',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('yalla-phase4-e2e-');
    final dbPath = '${temp.path}/accounts.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });
    final process = await Process.start(
        'node', ['test-support/onboarding-v4-fixture.mjs'],
        workingDirectory: controlRoot);
    final errors = StringBuffer();
    final err = process.stderr.transform(utf8.decoder).listen(errors.write);
    Future<void>? stdoutDrain;
    addTearDown(() async {
      process.stdin.writeln('close');
      try {
        await process.exitCode.timeout(const Duration(seconds: 10));
      } catch (_) {
        process.kill();
      }
      try {
        await stdoutDrain?.timeout(const Duration(seconds: 2));
      } catch (_) {}
      await err.cancel();
    });
    final lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    final info = await _readFixtureInfo(lines, {'base', 'auth_base', 'admin'});
    stdoutDrain = () async {
      while (await lines.moveNext()) {}
    }();
    const config = CloudAuthConfig(
        url: 'https://phase4-auth.example.invalid',
        publicKey: 'sb_publishable_phase4_fixture_only',
        releaseReady: true);
    SupabaseClient sdk() => SupabaseClient(info['auth_base'], config.publicKey,
        authOptions: AuthClientOptions(
            autoRefreshToken: false,
            pkceAsyncStorage:
                CloudPkceStorage(CloudSecureStorage('phase4-e2e'))));
    var cloud = sdk();
    var identity = SupabaseIdentityProvider(config, client: cloud);
    addTearDown(() async {
      identity.dispose();
      await cloud.dispose();
    });
    CustomerOnboardingClient transport() => CustomerOnboardingClient(
        baseUri: Uri.parse(info['base']),
        allowInsecureLoopbackForTesting: true,
        sessionProvider: () => identity.verifiedOnboardingSession());
    var client = transport();
    addTearDown(() => client.close());
    var service =
        CustomerOnboardingService(client: client, database: () async => db);
    const email = 'fresh-owner@phase4.invalid',
        password = 'real-fixture-password1';
    const draft = {
      'owner_name': 'Verified Owner',
      'organization_name': 'Fresh Paint Workshop',
      'phone': '+970599123456',
      'country_code': 'PS',
      'city': 'Hebron'
    };
    await identity.signUp(email, password);
    expect(await identity.verifiedAccessToken(), null);
    await expectLater(service.submit(draft), throwsA(anything));
    await expectLater(
        identity.verifySignupCode(email, '000000'), throwsA(anything));
    await identity.verifySignupCode(email, '123456');
    // Real Supabase OTP AMR is shared with recovery: login must follow OTP.
    expect(await identity.verifiedAccessToken(), null);
    await identity.signIn(email, password);
    final authUser = (await identity.verifiedOnboardingSession()).authUserId;
    // Match the current application flow: explicit consent is mandatory.
    await expectLater(
        service.submit(draft),
        throwsA(isA<CustomerOnboardingException>()
            .having((e) => e.status, 'consent must not be bypassed', 409)));
    final legal = HttpLegalAcceptanceService(
      baseUri: Uri.parse(info['base']),
      allowInsecureLoopbackForTesting: true,
      bearerTokenProvider: identity.verifiedAccessToken,
    );
    try {
      final accepted = await legal.accept(source: 'SIGNUP');
      expect(accepted.termsVersion, 'terms_ps_v1');
      expect(accepted.privacyVersion, 'privacy_ps_v1');
    } finally {
      legal.dispose();
    }
    final pending = await service.submit(draft);
    expect(pending.status, 'PENDING');
    expect(pending.operationalAccess, false);
    expect(await db.query('users'), isEmpty);
    expect(await db.query('license_activation_state'), isEmpty);
    expect((await service.submit(draft)).requestId, pending.requestId);
    await expectLater(service.submit({...draft, 'city': 'changed'}),
        throwsA(isA<CustomerOnboardingException>()));
    // Restore only the session actually created by the SDK login above.
    final persisted = jsonEncode(cloud.auth.currentSession!.toJson());
    identity.dispose();
    await cloud.dispose();
    client.close();
    await db.close();
    db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
    cloud = sdk();
    await cloud.auth.setInitialSession(persisted);
    identity = SupabaseIdentityProvider(config, client: cloud);
    client = transport();
    service =
        CustomerOnboardingService(client: client, database: () async => db);
    expect((await service.refresh()).status, 'PENDING');
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final listRequest = await http.getUrl(
        Uri.parse('${info['base']}/v1/control-center/onboarding-requests'));
    (info['admin'] as Map)
        .forEach((k, v) => listRequest.headers.set(k as String, v));
    final list =
        jsonDecode(await utf8.decoder.bind(await listRequest.close()).join())
            as Map;
    expect((list['items'] as List).single['request_id'], pending.requestId);
    final approval = await http.postUrl(Uri.parse(
        '${info['base']}/v1/control-center/customer-onboarding/approve'));
    approval.headers.contentType = ContentType.json;
    (info['admin'] as Map)
        .forEach((k, v) => approval.headers.set(k as String, v));
    approval.write(jsonEncode({'request_id': pending.requestId}));
    final approvalResponse = await approval.close();
    expect(approvalResponse.statusCode, 200);
    await approvalResponse.drain<void>();
    final approved = await service.refresh();
    expect(approved.status, 'APPROVED');
    expect(approved.data['license_status'], 'PENDING_ACTIVATION');
    expect(approved.data['activation_status'], 'ISSUED');
    expect(approved.data['started_at'], null);
    expect(approved.data.containsKey('activation_code'), false);
    expect(approved.operationalAccess, false);
    final otherCloud = sdk();
    addTearDown(otherCloud.dispose);
    await otherCloud.auth
        .signUp(email: 'other-owner@phase4.invalid', password: password);
    await otherCloud.auth.verifyOTP(
        email: 'other-owner@phase4.invalid',
        token: '123456',
        type: OtpType.signup);
    await otherCloud.auth.signInWithPassword(
        email: 'other-owner@phase4.invalid', password: password);
    final otherIdentity = SupabaseIdentityProvider(config, client: otherCloud);
    addTearDown(otherIdentity.dispose);
    await expectLater(
        client.send(await otherIdentity.verifiedOnboardingSession(), 'status',
            {'request_id': pending.requestId}),
        throwsA(isA<CustomerOnboardingException>()
            .having((e) => e.status, 'ownership denial', 404)));
    final local = (await db.query('pending_customer_onboarding')).single;
    expect(local['auth_user_id'], authUser);
    expect(local['owner_stage'], 'APPROVED_AWAITING_ACTIVATION');
    expect(jsonDecode(local['response_json']! as String)['organization_id'],
        approved.data['organization_id']);
    expect(await db.query('users'), isEmpty);
    expect(await db.query('license_activation_state'), isEmpty);
    expect(await db.query('gl_entries'), isEmpty);
    expect(await db.query('repairs'), isEmpty);
    expect(
        await ActivationStateRepository(databaseProvider: () async => db)
            .hasUsableActivationForCurrentInstallation(),
        false);
    await expectLater(
        FirstOwnerBootstrapService(databaseProvider: () async => db)
            .createFirstOwner(const FirstOwnerBootstrapRequest(
                ownerName: 'Verified Owner',
                password: 'Local-password-123',
                workshopName: 'Fresh Paint Workshop',
                workshopAddress: 'Street',
                country: 'فلسطين',
                province: 'الضفة الغربية',
                city: 'Hebron',
                street: 'Street',
                phone: '+970599123456')),
        throwsA(isA<FirstOwnerBootstrapException>()));
    final oldToken = await identity.verifiedAccessToken();
    await identity.signOut();
    expect(await identity.verifiedAccessToken(), null);
    await expectLater(service.refresh(), throwsA(anything));
    await expectLater(
        client
            .send(VerifiedOnboardingSession(authUser, oldToken!), 'status', {}),
        throwsA(isA<CustomerOnboardingException>()));
    await identity.resetPassword(email);
    await identity.verifyRecoveryCode(email, '123456');
    expect(await identity.verifiedAccessToken(), null);
    await expectLater(service.refresh(), throwsA(anything));
    await identity.updateRecoveredPassword('changed-fixture-password2');
    expect(await identity.verifiedAccessToken(), null);
    await identity.signIn(email, 'changed-fixture-password2');
    expect((await service.refresh()).status, 'APPROVED');
  },
      skip: controlRoot == null
          ? 'Set YALLA_CR1_CONTROL_ROOT to the isolated Control Server path'
          : false,
      timeout: const Timeout(Duration(minutes: 2)));
}
