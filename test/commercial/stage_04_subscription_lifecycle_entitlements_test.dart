import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/entitlements/commercial_entitlement_policy.dart';

VerifiedLicense _license({
  Map<String, Object?>? entitlements,
  String status = 'ACTIVE',
}) {
  final now = DateTime.now().toUtc();
  return VerifiedLicense(
    licenseId: '11111111-1111-4111-8111-111111111111',
    organizationId: '22222222-2222-4222-8222-222222222222',
    subscriptionId: '33333333-3333-4333-8333-333333333333',
    deviceId: '44444444-4444-4444-8444-444444444444',
    installationId: '55555555-5555-4555-8555-555555555555',
    issuedAt: now.subtract(const Duration(minutes: 5)),
    notBefore: now.subtract(const Duration(minutes: 5)),
    expiresAt: now.add(const Duration(days: 30)),
    entitlementRevision: 12,
    entitlements: entitlements ??
        const <String, Object?>{
          'PLAN_CODE': 'PRO',
          'ACCESS_ALLOWED': true,
          'ACCOUNTING_CORE': true,
          'MAX_USERS': 5,
          'MAX_DEVICES': 2,
          'WORKSHOP_REPAIRS': true,
        },
    validationRequiredAt: now.add(const Duration(days: 7)),
    validationGraceUntil: now.add(const Duration(days: 14)),
    operationalStatus: status,
  );
}

void main() {
  final root = Directory.current.path;

  String read(String relative) =>
      File('$root${Platform.pathSeparator}$relative').readAsStringSync();

  test('Stage 04 validates core signed entitlement types fail-closed', () {
    expect(CommercialEntitlementPolicy.evaluate(_license()).valid, isTrue);

    final noAccounting = CommercialEntitlementPolicy.evaluate(
      _license(
        entitlements: const <String, Object?>{
          'PLAN_CODE': 'PRO',
          'ACCESS_ALLOWED': true,
          'ACCOUNTING_CORE': false,
          'MAX_USERS': 5,
          'MAX_DEVICES': 2,
        },
      ),
    );
    expect(noAccounting.valid, isTrue);
    expect(
        CommercialEntitlementPolicy.isEnabled(
          _license(entitlements: const <String, Object?>{
            'PLAN_CODE': 'PARTS_ONLY',
            'ACCESS_ALLOWED': true,
            'ACCOUNTING_CORE': false,
            'MAX_USERS': 5,
            'MAX_DEVICES': 2,
          }),
          'ACCOUNTING_CORE',
        ),
        isFalse);

    final badUsers = CommercialEntitlementPolicy.evaluate(
      _license(
        entitlements: const <String, Object?>{
          'PLAN_CODE': 'PRO',
          'ACCESS_ALLOWED': true,
          'ACCOUNTING_CORE': true,
          'MAX_USERS': 0,
          'MAX_DEVICES': 2,
        },
      ),
    );
    expect(badUsers.valid, isFalse);
    expect(badUsers.code, 'MAX_USERS_INVALID');

    final badDevices = CommercialEntitlementPolicy.evaluate(
      _license(
        entitlements: const <String, Object?>{
          'PLAN_CODE': 'PRO',
          'ACCESS_ALLOWED': true,
          'ACCOUNTING_CORE': true,
          'MAX_USERS': 5,
          'MAX_DEVICES': '2',
        },
      ),
    );
    expect(badDevices.valid, isFalse);
    expect(badDevices.code, 'MAX_DEVICES_INVALID');

    final badFeature = CommercialEntitlementPolicy.evaluate(
      _license(
        entitlements: const <String, Object?>{
          'PLAN_CODE': 'PRO',
          'ACCESS_ALLOWED': true,
          'ACCOUNTING_CORE': true,
          'MAX_USERS': 5,
          'MAX_DEVICES': 2,
          'INVENTORY': 1,
        },
      ),
    );
    expect(badFeature.valid, isFalse);
    expect(badFeature.code, 'ENTITLEMENT_TYPE_INVALID');

    final badPlan = CommercialEntitlementPolicy.evaluate(_license(
      entitlements: const <String, Object?>{
        'PLAN_CODE': '',
        'ACCESS_ALLOWED': true,
        'MAX_USERS': 5,
        'MAX_DEVICES': 2,
      },
    ));
    expect(badPlan.code, 'PLAN_CODE_INVALID');

    final badAccess = CommercialEntitlementPolicy.evaluate(_license(
      entitlements: const <String, Object?>{
        'PLAN_CODE': 'PRO',
        'ACCESS_ALLOWED': 'yes',
        'MAX_USERS': 5,
        'MAX_DEVICES': 2,
      },
    ));
    expect(badAccess.code, 'ACCESS_ALLOWED_INVALID');
  });

  test('Stage 04 commercial gate consumes signed entitlement policy', () {
    final gate = read(
      'lib/features/auth/services/commercial_access_gate_service.dart',
    );
    expect(gate, contains('CommercialEntitlementPolicy.evaluate(license)'));
    final policy = read(
      'lib/core/licensing/entitlements/commercial_entitlement_policy.dart',
    );
    expect(policy, contains("'PLAN_CODE_INVALID'"));
    expect(policy, contains("'ACCESS_ALLOWED_INVALID'"));
    expect(read('lib/core/licensing/lifecycle/subscription_access_policy.dart'),
        contains("'ACTIVE'"));
    expect(read('lib/core/licensing/lifecycle/subscription_access_policy.dart'),
        contains("'GRACE'"));
    expect(read('lib/core/licensing/lifecycle/subscription_access_policy.dart'),
        contains("'SUSPENDED'"));
    expect(read('lib/core/licensing/lifecycle/subscription_access_policy.dart'),
        contains("'EXPIRED'"));
    expect(read('lib/core/licensing/lifecycle/subscription_access_policy.dart'),
        contains("'REVOKED'"));
    expect(read('lib/core/licensing/lifecycle/subscription_access_policy.dart'),
        contains("'CANCELLED'"));
  });

  test('Stage 04 disables legacy local trial and subscription authority', () {
    final oldLicense = read('lib/core/services/license_service.dart');
    final oldManager = read('lib/core/licensing/license_manager.dart');
    final authSubscription =
        read('lib/features/auth/services/subscription_service.dart');
    final subscription =
        read('lib/features/subscription/services/subscription_service.dart');
    final plans = read('lib/features/subscription/services/plan_service.dart');

    expect(oldLicense, contains('SERVER_AUTHORITY_REQUIRED'));
    expect(oldLicense, isNot(contains('SharedPreferences')));
    expect(oldLicense, isNot(contains("package:uuid/uuid.dart")));
    expect(oldManager, isNot(contains('trial_manager.dart')));
    expect(authSubscription, contains('SERVER_AUTHORITY_REQUIRED'));
    expect(authSubscription, isNot(contains('openDatabase(')));
    expect(subscription, contains('SERVER_AUTHORITY_REQUIRED'));
    expect(subscription, isNot(contains("db.insert('subscriptions'")));
    expect(plans, contains('SERVER_AUTHORITY_REQUIRED'));
    expect(plans, isNot(contains("db.query('plans'")));
  });

  test('Stage 04 UI no longer creates or trusts local subscription state', () {
    final splash = read('lib/features/splash/screens/splash_screen.dart');
    final dashboard =
        read('lib/features/auth/screens/user_dashboard_screen.dart');
    final subscription =
        read('lib/features/subscription/screens/subscription_screen.dart');
    final current = read(
        'lib/features/subscription/screens/current_subscription_screen.dart');
    final pending = read(
        'lib/features/subscription/screens/pending_subscriptions_screen.dart');

    expect(splash, isNot(contains('SubscriptionService')));
    expect(splash, isNot(contains('freeTrialEnd')));
    expect(dashboard, isNot(contains('user.freeTrialEnd')));
    expect(dashboard, isNot(contains('user.subscriptionEndDate')));
    expect(
        subscription, contains('loadAuthenticLicenseForCurrentInstallation'));
    expect(subscription, isNot(contains('activateTrial')));
    expect(subscription, isNot(contains('PlanService')));
    expect(current, contains('refreshFromStoredLicense'));
    expect(current, isNot(contains('PlanService')));
    expect(current, isNot(contains('SubscriptionService')));
    expect(pending, isNot(contains('createSubscription')));
    expect(pending, isNot(contains('updateUser')));
  });

  test('Stage 04 preserves server-side lifecycle and entitlement boundaries',
      () {
    final lifecycle = read(
      'server/yalla_licensing_server/database/model/sec_011_lifecycle_invariants.md',
    );
    final entitlements = read(
      'server/yalla_licensing_server/database/model/sec_003_entitlement_invariants.md',
    );

    expect(lifecycle, contains('Customer accounting data is never deleted'));
    expect(lifecycle, contains('READ ONLY'));
    expect(
        lifecycle, contains('desktop cannot self-declare subscription state'));
    expect(entitlements, contains('server is the commercial source of truth'));
    expect(
      entitlements,
      contains('active subscription override > plan entitlement'),
    );
  });
}
