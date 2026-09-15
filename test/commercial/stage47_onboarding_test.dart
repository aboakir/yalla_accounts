import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_service.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/activation/screens/activation_screen.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/login_screen.dart';
import 'package:yalla_accounts/features/auth/screens/register_user_screen.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/services/device_unlock_service.dart';
import 'package:yalla_accounts/features/auth/services/first_owner_bootstrap_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/services/yalla_admin_auth_service.dart';
import 'package:yalla_accounts/features/onboarding/screens/workshop_onboarding_completion_screen.dart';
import 'package:yalla_accounts/features/onboarding/screens/workshop_onboarding_screen.dart';
import 'package:yalla_accounts/features/onboarding/services/workshop_onboarding_service.dart';
import 'package:yalla_accounts/features/onboarding/services/workshop_onboarding_tables.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

AppUser owner({String role = 'owner', String organization = 'org'}) => AppUser(
      id: 'owner-id',
      name: 'مالك الورشة',
      email: '',
      role: role,
      isOwner: role == 'owner',
      organizationId: organization,
      identityAccountId: 'person-id',
      status: 'active',
      createdAt: DateTime(2026),
    );

VerifiedLicense license(
    {String status = 'ACTIVE', Map<String, Object?>? entitlements}) {
  final now = DateTime.now().toUtc();
  return VerifiedLicense(
      licenseId: 'license',
      organizationId: 'org',
      subscriptionId: 'subscription',
      deviceId: 'real-device',
      installationId: 'installation',
      issuedAt: now.subtract(const Duration(days: 1)),
      notBefore: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 30)),
      entitlementRevision: 1,
      entitlements: entitlements ??
          const {
            'PLAN_CODE': 'PRO',
            'ACCESS_ALLOWED': true,
            'ACCOUNTING_CORE': true,
            'MAX_USERS': 5,
            'MAX_DEVICES': 2,
          },
      validationRequiredAt: now.add(const Duration(days: 7)),
      validationGraceUntil: now.add(const Duration(days: 14)),
      operationalStatus: status);
}

class Progress extends WorkshopOnboardingService {
  bool pending = true;
  bool licensed = true;
  bool failComplete = false;
  int saves = 0;
  int completions = 0;
  bool? backup;
  @override
  Future<bool> needsCompletion(AppUser user) async => pending;
  @override
  Future<VerifiedLicense?> loadSetupLicense() async =>
      licensed ? license() : null;
  @override
  Future<CommercialSettings> loadCommercialSettings() async =>
      const CommercialSettings(
          countryCode: 'PS',
          baseCurrencyCode: 'ILS',
          currencySymbol: '₪',
          currencyDecimals: 2,
          defaultVatRate: 0,
          pricesIncludeVat: false,
          taxRegistrationNumber: '');
  @override
  Future<void> saveCurrency(CountryPreset selected) async {
    saves++;
  }

  @override
  Future<void> complete(AppUser user, {required bool openBackup}) async {
    if (failComplete) throw StateError('تعذر حفظ التقدم');
    pending = false;
    completions++;
    backup = openBackup;
  }
}

class Gate extends CommercialAccessGateService {
  bool allowed = true;
  bool readOnly = false;
  @override
  Future<CommercialAccessDecision> evaluate(AppUser user) async => allowed
      ? CommercialAccessDecision.allow(
          readOnly: readOnly,
          code: 'OK',
          message: '',
          license: license(status: readOnly ? 'EXPIRED' : 'ACTIVE'))
      : const CommercialAccessDecision.deny(
          code: 'ACTIVATION_REQUIRED',
          message: 'تفعيل الجهاز مطلوب',
          requiresActivation: true);
}

class Session extends AuthSessionService {
  int creates = 0;
  bool failCreate = false;
  int logouts = 0;
  AppUser? saved;
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
    creates++;
    saved = user;
    if (failCreate) throw StateError('storage failed');
    return 'session';
  }

  @override
  Future<void> logout() async {
    logouts++;
    saved = null;
  }
}

class Unlock extends DeviceUnlockService {
  bool fail = false;
  bool configured = false;
  int writes = 0;
  @override
  Future<bool> biometricAvailable() async => false;
  @override
  Future<bool> biometricEnabledFor(String userId) async => false;
  @override
  Future<bool> isConfiguredFor(String userId) async => configured;
  @override
  Future<bool> verifyPin({required String userId, required String pin}) async =>
      configured && pin == '1234';
  @override
  Future<void> configure(
      {required String userId,
      required String pin,
      required bool enableBiometric}) async {
    writes++;
    if (fail) throw StateError('unavailable');
    configured = true;
  }
}

class Users extends UserService {
  bool existing = true;
  int bootstraps = 0;
  FirstOwnerBootstrapRequest? request;
  @override
  Future<bool> hasAnyUsers() async => existing;
  @override
  Future<AppUser?> authenticateUser(String username, String password) async =>
      password == 'password123' ? owner() : null;
  @override
  Future<AppUser?> getUserById(String id) async => owner();
  @override
  Future<FirstOwnerBootstrapResult> bootstrapFirstOwner(
      FirstOwnerBootstrapRequest value) async {
    bootstraps++;
    request = value;
    existing = true;
    return const FirstOwnerBootstrapResult(
        ownerUserId: 'owner-id', recoveryCode: 'YA-TEST-CODE');
  }
}

class Phone extends YallaAdminAuthService {
  int consumed = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<CustomerPhoneOtpChallenge> startCustomerPhoneVerification(
          {required String phone}) async =>
      const CustomerPhoneOtpChallenge(
          challengeId: 'challenge',
          expiresInSeconds: 300,
          resendAfterSeconds: 30,
          delivery: 'sms');
  @override
  Future<CustomerPhoneVerification> verifyCustomerPhoneOtp(
          {required String challengeId, required String code}) async =>
      const CustomerPhoneVerification(
          challengeId: 'challenge',
          phone: '0599999999',
          verificationToken: 'proof');
  @override
  Future<void> consumeCustomerPhoneVerification(
      {required String challengeId,
      required String phone,
      required String verificationToken}) async {
    consumed++;
  }
}

class Activation extends ActivationService {
  bool fail = false;
  String? code;
  @override
  bool get isConfigured => true;
  @override
  Future<VerifiedLicense> activateFirstInstallation(
      String activationCode) async {
    code = activationCode;
    if (fail) throw StateError('invalid');
    return license();
  }
}

Future<ProviderContainer> harness(WidgetTester tester, Widget home,
    {Progress? progress,
    Gate? gate,
    Session? session,
    Unlock? unlock,
    Users? users,
    Phone? phone,
    Size size = const Size(850, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    workshopOnboardingServiceProvider.overrideWithValue(progress ?? Progress()),
    commercialAccessGateServiceProvider.overrideWithValue(gate ?? Gate()),
    authSessionServiceProvider.overrideWithValue(session ?? Session()),
    deviceUnlockServiceProvider.overrideWithValue(unlock ?? Unlock()),
    userServiceProvider.overrideWithValue(users ?? Users()),
    yallaAdminAuthServiceProvider.overrideWithValue(phone ?? Phone()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: home, routes: {
        AppRoutes.dashboard: (_) => const Scaffold(body: Text('DASHBOARD')),
        AppRoutes.settingsSecurityData: (_) =>
            const Scaffold(body: Text('BACKUP SETTINGS')),
        AppRoutes.login: (_) => const Scaffold(body: Text('LOGIN')),
        AppRoutes.activation: (_) => const Scaffold(body: Text('ACTIVATION')),
        AppRoutes.register: (_) => const Scaffold(body: Text('REGISTER')),
      })));
  await tester.pumpAndSettle();
  return container;
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> setField(WidgetTester tester, String label, String value) async {
  final finder = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

Future<void> configurePin(WidgetTester tester) async {
  await tap(tester, 'متابعة إلى إعداد PIN');
  await setField(tester, 'PIN من 4 إلى 6 أرقام', '١٢٣٤');
  await setField(tester, 'تأكيد PIN', '1234');
  await tap(tester, 'حفظ والمتابعة');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
      'signed setup eligibility rejects expired, frozen, demo and invalid entitlements',
      () {
    expect(WorkshopOnboardingService.canStart(license()), isTrue);
    for (final status in [
      'EXPIRED',
      'FROZEN',
      'CANCELLED',
      'DEMO',
      'unknown'
    ]) {
      expect(
          WorkshopOnboardingService.canStart(license(status: status)), isFalse,
          reason: status);
    }
    expect(
        WorkshopOnboardingService.canStart(license(entitlements: const {
          'PLAN_CODE': 'PRO',
          'ACCESS_ALLOWED': true,
          'ACCOUNTING_CORE': true,
          'MAX_USERS': 0,
          'MAX_DEVICES': 1,
        })),
        isFalse);
  });

  test(
      'bootstrap progress is atomic, survives service restart and leaves existing workshops alone',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE organizations(id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE users(id TEXT PRIMARY KEY)');
    await db.execute(
        'CREATE TABLE owner_bootstrap_state(status TEXT, owner_user_id TEXT, organization_id TEXT, updated_at TEXT)');
    await db.insert('organizations', {'id': 'org'});
    await db.insert('users', {'id': 'owner-id'});
    await db.insert('owner_bootstrap_state', {
      'status': 'COMPLETED',
      'owner_user_id': 'owner-id',
      'organization_id': 'org',
      'updated_at': 'now'
    });
    await WorkshopOnboardingTables.ensure(db);
    final service = WorkshopOnboardingService(databaseProvider: () async => db);
    expect(await service.needsCompletion(owner()), isFalse);
    await db.update('owner_bootstrap_state', {'status': 'PENDING'});
    await expectLater(db.transaction((txn) async {
      await txn.update('owner_bootstrap_state', {'status': 'COMPLETED'});
      throw StateError('simulated bootstrap rollback');
    }), throwsStateError);
    expect(await service.needsCompletion(owner()), isFalse);
    await db.update('owner_bootstrap_state', {'status': 'COMPLETED'});
    final restarted =
        WorkshopOnboardingService(databaseProvider: () async => db);
    expect(await restarted.needsCompletion(owner()), isTrue);
    expect(await restarted.needsCompletion(owner(role: 'staff')), isFalse);
    expect(await restarted.needsCompletion(owner(organization: 'different')),
        isFalse);
    await expectLater(
        restarted.complete(owner(role: 'staff'), openBackup: false),
        throwsStateError);
    await restarted.complete(owner(), openBackup: false);
    expect(await service.needsCompletion(owner()), isFalse);
    expect(
        (await db.query('workshop_onboarding_state')).single['backup_choice'],
        'later');
  });

  for (final existing in [false, true]) {
    testWidgets(
        'activation delegates device binding and routes existing=$existing correctly',
        (tester) async {
      final activation = Activation()..fail = true;
      await harness(tester, ActivationScreen(service: activation),
          users: Users()..existing = existing);
      await setField(tester, 'رمز التفعيل', 'SERVER-CODE');
      await tap(tester, 'تفعيل الجهاز');
      expect(find.textContaining('تعذر إكمال التفعيل'), findsOneWidget);
      expect(find.text('REGISTER'), findsNothing);
      activation.fail = false;
      await tap(tester, 'تفعيل الجهاز');
      expect(activation.code, 'SERVER-CODE');
      expect(find.text(existing ? 'LOGIN' : 'REGISTER'), findsOneWidget);
    });
  }

  testWidgets('new unactivated workshop cannot open account creation',
      (tester) async {
    await harness(tester, const WorkshopOnboardingScreen(),
        users: Users()..existing = false,
        progress: Progress()..licensed = false);
    expect(find.text('متابعة إنشاء حساب المالك'), findsNothing);
    await tap(tester, 'بدء تفعيل الجهاز');
    expect(find.text('ACTIVATION'), findsOneWidget);
  });

  testWidgets(
      'existing workshop is sent to existing login, never second owner creation',
      (tester) async {
    await harness(tester, const WorkshopOnboardingScreen());
    expect(find.text('متابعة إنشاء حساب المالك'), findsNothing);
    await tap(tester, 'الدخول إلى الورشة الحالية');
    expect(find.text('LOGIN'), findsOneWidget);
  });

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('PIN failure/cancel preserves pending setup at ${size.width}',
        (tester) async {
      final progress = Progress();
      final session = Session();
      final unlock = Unlock()..fail = true;
      final container = await harness(
          tester, WorkshopOnboardingCompletionScreen(user: owner()),
          progress: progress, session: session, unlock: unlock, size: size);
      await configurePin(tester);
      expect(
          find.textContaining('تعذر حفظ حماية الجهاز بأمان'), findsOneWidget);
      expect(session.creates, 0);
      expect(progress.pending, isTrue);
      expect(container.read(currentUserProvider), isNull);
      await tap(tester, 'إلغاء');
      expect(find.textContaining('لم يكتمل إعداد PIN'), findsOneWidget);
      await tap(tester, 'إكمال لاحقًا والعودة للدخول');
      expect(find.text('LOGIN'), findsOneWidget);
      expect(progress.pending, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final backup in [false, true]) {
    testWidgets(
        'PIN verified before session; backup choice $backup enters real route',
        (tester) async {
      final progress = Progress();
      final session = Session();
      final container = await harness(
          tester, WorkshopOnboardingCompletionScreen(user: owner()),
          progress: progress, session: session);
      await configurePin(tester);
      expect(session.creates, 0);
      await tap(
          tester,
          backup
              ? 'فتح إعداد النسخ الاحتياطي'
              : 'لاحقًا — الدخول إلى لوحة التحكم');
      expect(session.creates, 1);
      expect(progress.pending, isFalse);
      expect(progress.backup, backup);
      expect(container.read(currentUserProvider)?.id, 'owner-id');
      expect(
          find.text(backup ? 'BACKUP SETTINGS' : 'DASHBOARD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('license revoked between PIN and finish creates no session',
      (tester) async {
    final gate = Gate();
    final session = Session();
    final progress = Progress();
    final container = await harness(
        tester, WorkshopOnboardingCompletionScreen(user: owner()),
        progress: progress, session: session, gate: gate);
    await configurePin(tester);
    gate.allowed = false;
    await tap(tester, 'لاحقًا — الدخول إلى لوحة التحكم');
    expect(session.creates, 0);
    expect(progress.pending, isTrue);
    expect(container.read(currentUserProvider), isNull);
    expect(find.text('تفعيل الجهاز مطلوب'), findsOneWidget);
  });

  testWidgets('expired owner may finish security without rewriting currency',
      (tester) async {
    final progress = Progress();
    await harness(tester, WorkshopOnboardingCompletionScreen(user: owner()),
        progress: progress, gate: Gate()..readOnly = true);
    await configurePin(tester);
    expect(progress.saves, 0);
    await tap(tester, 'لاحقًا — الدخول إلى لوحة التحكم');
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets(
      'progress save failure logs out and retry resumes without losing owner',
      (tester) async {
    final progress = Progress()..failComplete = true;
    final session = Session();
    final container = await harness(
        tester, WorkshopOnboardingCompletionScreen(user: owner()),
        progress: progress, session: session);
    await configurePin(tester);
    await tap(tester, 'لاحقًا — الدخول إلى لوحة التحكم');
    expect(session.logouts, 1);
    expect(session.saved, isNull);
    expect(progress.pending, isTrue);
    expect(container.read(currentUserProvider), isNull);
    progress.failComplete = false;
    await tap(tester, 'لاحقًا — الدخول إلى لوحة التحكم');
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(progress.completions, 1);
  });

  testWidgets('non-owner cannot use pending setup to authenticate',
      (tester) async {
    final session = Session();
    await harness(
        tester, WorkshopOnboardingCompletionScreen(user: owner(role: 'staff')),
        session: session);
    expect(find.text('متابعة إلى إعداد PIN'), findsNothing);
    expect(session.creates, 0);
  });

  testWidgets(
      'authenticated password login resumes pending workshop before session creation',
      (tester) async {
    final session = Session();
    await harness(tester, const LoginScreen(), session: session);
    await setField(tester, 'اسم المستخدم', 'مالك الورشة');
    await setField(tester, 'كلمة المرور', 'password123');
    await tap(tester, 'دخول');
    expect(find.byType(WorkshopOnboardingCompletionScreen), findsOneWidget);
    expect(session.creates, 0);
  });

  testWidgets(
      'new owner saves contact/workshop data and safely retries failed PIN',
      (tester) async {
    final users = Users()..existing = false;
    final phone = Phone();
    final unlock = Unlock()..fail = true;
    final session = Session();
    await harness(tester, const RegisterUserScreen(),
        users: users, phone: phone, unlock: unlock, session: session);
    await setField(tester, 'اسم المالك', 'مالك الورشة');
    await setField(tester, 'كلمة المرور', 'password123');
    await setField(tester, 'تأكيد كلمة المرور', 'password123');
    await tap(tester, 'التالي');
    await setField(tester, 'رقم الهاتف', '0599999999');
    await tap(tester, 'التالي');
    expect(users.bootstraps, 0);
    await setField(tester, 'اسم الورشة', 'ورشة القدس');
    await setField(tester, 'المدينة', 'الخليل');
    await tap(tester, 'إنشاء الحساب ومتابعة الإعداد');
    expect(find.text('YA-TEST-CODE'), findsOneWidget);
    expect(phone.consumed, 0);
    expect(users.request!.workshopName, 'ورشة القدس');
    expect(users.request!.city, 'الخليل');
    expect(users.request!.phone, '0599999999');
    expect(session.creates, 0);
    await tap(tester, 'حفظته');
    await configurePin(tester);
    expect(find.textContaining('تعذر حفظ حماية الجهاز بأمان'), findsOneWidget);
    unlock.fail = false;
    await configurePin(tester);
    await tap(tester, 'لاحقًا — الدخول إلى لوحة التحكم');
    expect(users.bootstraps, 1);
    expect(phone.consumed, 0);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'session storage failure clears partial login and leaves setup pending',
      (tester) async {
    final progress = Progress();
    final session = Session()..failCreate = true;
    final container = await harness(
        tester, WorkshopOnboardingCompletionScreen(user: owner()),
        progress: progress, session: session);
    await configurePin(tester);
    await tap(tester, 'لاحقًا — الدخول إلى لوحة التحكم');
    expect(session.saved, isNull);
    expect(session.logouts, 1);
    expect(progress.pending, isTrue);
    expect(container.read(currentUserProvider), isNull);
  });

  test(
      'onboarding currency preserves tax settings and rejects relabelling existing money',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
        'CREATE TABLE workshop_settings(id INTEGER PRIMARY KEY, country_code TEXT, base_currency_code TEXT, currency_symbol TEXT, currency_decimals INTEGER, default_vat_rate REAL, prices_include_vat INTEGER, tax_registration_number TEXT, updated_at TEXT)');
    await db.insert('workshop_settings', {
      'id': 1,
      'country_code': 'PS',
      'base_currency_code': 'ILS',
      'currency_symbol': '₪',
      'currency_decimals': 2,
      'default_vat_rate': 17.0,
      'prices_include_vat': 1,
      'tax_registration_number': 'TAX-ORIGINAL'
    });
    for (final table in [
      'gl_entries',
      'invoices',
      'purchase_invoices',
      'payments',
      'vouchers'
    ]) {
      await db.execute('CREATE TABLE $table(id INTEGER PRIMARY KEY)');
    }
    final service = WorkshopOnboardingService(databaseProvider: () async => db);
    await service.saveCurrency(CommercialSettingsService.presets[1]);
    final settings = await service.loadCommercialSettings();
    expect(settings.baseCurrencyCode, 'JOD');
    expect(settings.defaultVatRate, 17);
    expect(settings.pricesIncludeVat, isTrue);
    expect(settings.taxRegistrationNumber, 'TAX-ORIGINAL');
    expect(settings.countryCode, 'PS');
    await db.insert('gl_entries', {'id': 1});
    await expectLater(
        service.saveCurrency(CommercialSettingsService.presets.first),
        throwsStateError);
    expect((await service.loadCommercialSettings()).baseCurrencyCode, 'JOD');
  });
}
