import 'package:yalla_accounts/features/auth/widgets/authenticated_route_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/screens/login_screen.dart';
import 'package:yalla_accounts/features/startup/startup_screen.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/services/device_unlock_service.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';

AppUser actor(String role) => AppUser(
    id: 'real-user',
    name: 'owner',
    email: '',
    role: role,
    status: 'active',
    createdAt: DateTime(2026));

class Users extends UserService {
  Users(this.user);
  final AppUser? user;
  int attempts = 0;
  @override
  Future<bool> hasAnyUsers() async => true;
  @override
  Future<AppUser?> authenticateUser(String name, String password) async {
    attempts++;
    return name == 'owner' && password == 'valid-password' ? user : null;
  }
}

class Session extends AuthSessionService {
  AppUser? saved;
  int created = 0;
  @override
  Future<LoginPreferences> loadLoginPreferences() async =>
      const LoginPreferences(rememberUsername: false, keepSignedIn: false);
  @override
  Future<AppUser?> restoreSession() async => saved;
  @override
  Future<void> saveLoginPreferences(
      {required String username,
      required bool rememberUsername,
      required bool keepSignedIn}) async {}
  @override
  Future<String> createSession(AppUser user,
      {bool keepSignedIn = false}) async {
    created++;
    saved = user;
    return 'fixture';
  }

  @override
  Future<void> logout() async {
    saved = null;
  }
}

class Access extends CommercialAccessGateService {
  Access(this.allowed);
  final bool allowed;
  @override
  Future<CommercialAccessDecision> evaluate(AppUser user) async {
    if (!allowed) {
      return const CommercialAccessDecision.deny(
          code: 'ACTIVATION_REQUIRED',
          message: 'التفعيل مطلوب',
          requiresActivation: true);
    }
    final now = DateTime.now();
    return CommercialAccessDecision.allow(
        readOnly: false,
        code: 'VALID',
        message: '',
        license: VerifiedLicense(
            licenseId: 'l',
            organizationId: 'o',
            subscriptionId: 's',
            deviceId: 'd',
            installationId: 'i',
            issuedAt: now,
            notBefore: now,
            expiresAt: now.add(const Duration(days: 1)),
            entitlementRevision: 1,
            entitlements: const {},
            validationRequiredAt: now,
            validationGraceUntil: now.add(const Duration(days: 1)),
            operationalStatus: 'ACTIVE'));
  }
}

class Unlock extends DeviceUnlockService {
  Unlock(this.configured);
  final bool configured;
  @override
  Future<bool> isConfiguredFor(String id) async => configured;
  @override
  Future<bool> biometricEnabledFor(String id) async => false;
  @override
  Future<bool> verifyPin({required String userId, required String pin}) async =>
      pin == '1234';
}

class CancelledBiometric extends Unlock {
  CancelledBiometric() : super(true);
  @override
  Future<bool> biometricEnabledFor(String id) async => true;
  @override
  Future<bool> authenticateBiometric({required String userId}) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final role in [
    'Owner',
    'Admin',
    'Accountant',
    'Staff',
    'Viewer',
    'Employee'
  ]) {
    testWidgets('password login preserves canonical $role', (t) async {
      final users = Users(actor(role));
      final session = Session();
      final c = ProviderContainer(overrides: [
        userServiceProvider.overrideWithValue(users),
        authSessionServiceProvider.overrideWithValue(session),
        commercialAccessGateServiceProvider.overrideWithValue(Access(true)),
        deviceUnlockServiceProvider.overrideWithValue(Unlock(false))
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
              home: const LoginScreen(),
              routes: {
                '/dashboard': (_) => const Text('OPENED'),
                '/repairs/dashboard': (_) => const Text('OPENED')
              },
              onGenerateRoute: (_) =>
                  MaterialPageRoute(builder: (_) => const Text('OPENED')))));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'owner');
      await t.enterText(find.byType(TextField).last, 'wrong');
      await t.tap(find.text('دخول'));
      await t.pumpAndSettle();
      expect(session.created, 0);
      expect(c.read(currentUserProvider), isNull);
      await t.enterText(find.byType(TextField).last, 'valid-password');
      await t.tap(find.text('دخول'));
      await t.pumpAndSettle();
      expect(session.created, 1);
      expect(c.read(currentUserProvider)?.role, role.toLowerCase());
      expect(find.text('OPENED'), findsOneWidget);
    });
  }
  for (final configured in [false, true]) {
    testWidgets(
        'startup does not open persisted owner without unlock: $configured',
        (t) async {
      final session = Session()..saved = actor('owner');
      final c = ProviderContainer(overrides: [
        userServiceProvider.overrideWithValue(Users(actor('owner'))),
        authSessionServiceProvider.overrideWithValue(session),
        commercialAccessGateServiceProvider.overrideWithValue(Access(false)),
        deviceUnlockServiceProvider.overrideWithValue(Unlock(configured))
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
              home: const StartupScreen(),
              routes: {'/login': (_) => const LoginScreen()})));
      await t.pumpAndSettle();
      expect(c.read(currentUserProvider), isNull);
      if (configured) {
        await t.enterText(find.byType(TextField).first, '1234');
        await t.tap(find.text('فتح التطبيق'));
      } else {
        await t.enterText(find.byType(TextField).first, 'owner');
        await t.enterText(find.byType(TextField).last, 'valid-password');
        await t.tap(find.text('دخول'));
      }
      await t.pumpAndSettle();
      expect(find.text('التفعيل مطلوب'), findsOneWidget);
      expect(c.read(currentUserProvider), isNull);
      expect(session.created, 0);
    });
  }
  test('PIN lockout persists across service instances and wrong user is denied',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final service = DeviceUnlockService();
    await service.configure(
        userId: 'owner', pin: '1234', enableBiometric: false);
    expect(await service.verifyPin(userId: 'another', pin: '1234'), isFalse);
    for (var i = 0; i < 5; i++) {
      expect(await service.verifyPin(userId: 'owner', pin: '0000'), isFalse);
    }
    expect(await DeviceUnlockService().verifyPin(userId: 'owner', pin: '1234'),
        isFalse);
    await service.clear();
    expect(await service.isConfiguredFor('owner'), isFalse);
  });
  for (final mode in ['valid', 'no-session', 'unlicensed', 'stale-role']) {
    testWidgets('protected route validates real session: $mode', (t) async {
      final session = Session()
        ..saved = mode == 'no-session' ? null : actor('owner');
      final c = ProviderContainer(overrides: [
        authSessionServiceProvider.overrideWithValue(session),
        commercialAccessGateServiceProvider
            .overrideWithValue(Access(mode != 'unlicensed'))
      ]);
      addTearDown(c.dispose);
      c.read(currentUserProvider.notifier).state =
          actor(mode == 'stale-role' ? 'employee' : 'owner');
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
              home: AuthenticatedRouteGate(child: Text('PROTECTED')))));
      await t.pumpAndSettle();
      expect(find.text('PROTECTED'),
          mode == 'valid' ? findsOneWidget : findsNothing);
      c.read(currentUserProvider.notifier).state = null;
      await t.pumpAndSettle();
      expect(find.text('PROTECTED'), findsNothing);
    });
  }
  testWidgets(
      'RTL persisted login requires PIN and biometric cancellation falls back safely',
      (t) async {
    final session = Session()..saved = actor('owner');
    final c = ProviderContainer(overrides: [
      userServiceProvider.overrideWithValue(Users(actor('owner'))),
      authSessionServiceProvider.overrideWithValue(session),
      commercialAccessGateServiceProvider.overrideWithValue(Access(true)),
      deviceUnlockServiceProvider.overrideWithValue(CancelledBiometric()),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: const StartupScreen(), routes: {
          '/login': (_) => const LoginScreen(),
          '/dashboard': (_) => const Text('UNLOCKED'),
        })));
    await t.pumpAndSettle();
    expect(c.read(currentUserProvider), isNull);
    expect(Directionality.of(t.element(find.text('فتح التطبيق'))),
        TextDirection.rtl);
    await t.tap(find.text('استخدام البصمة / Face ID'));
    await t.pumpAndSettle();
    expect(c.read(currentUserProvider), isNull);
    await t.enterText(find.byType(TextField).first, '0000');
    await t.tap(find.text('فتح التطبيق'));
    await t.pumpAndSettle();
    expect(c.read(currentUserProvider), isNull);
    await t.enterText(find.byType(TextField).first, '1234');
    await t.tap(find.text('فتح التطبيق'));
    await t.pumpAndSettle();
    expect(find.text('UNLOCKED'), findsOneWidget);
    expect(c.read(currentUserProvider)?.role, 'owner');
    expect(session.created, 0,
        reason: 'Unlock must not create duplicate sessions');
    expect(t.takeException(), isNull);
  });
}
