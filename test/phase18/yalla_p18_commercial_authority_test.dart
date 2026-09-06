import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;

  String read(String relative) =>
      File('$root${Platform.pathSeparator}$relative').readAsStringSync();

  test('P18 removes the runtime authentication development bypass', () {
    final routes = read('lib/core/routes/app_routes.dart');
    final marker = read('lib/dev/temporary_auth_bypass.dart');

    expect(routes, isNot(contains('kTemporaryAuthBypass')));
    expect(routes, isNot(contains('YALLA_TEMP_AUTH_BYPASS')));
    expect(marker, contains('kTemporaryAuthBypass = false'));
  });

  test('P18 removes local repair-count trial gating', () {
    final dashboard = read('lib/features/home/screens/dashboard_screen.dart');
    final sidebar = read('lib/core/widgets/sidebar/yalla_sidebar.dart');

    expect(dashboard, isNot(contains('maxFreeRepairs')));
    expect(dashboard, isNot(contains('_canAddNewRepair')));
    expect(sidebar, isNot(contains('maxFreeRepairs')));
    expect(sidebar, isNot(contains('_canAddNewRepairFromSidebar')));
  });

  test('P18 keeps commercial state server-authoritative', () {
    final policy = read(
      'lib/core/licensing/entitlements/commercial_entitlement_policy.dart',
    );
    final legacyTrial = read('lib/core/licensing/trial_manager.dart');
    final legacyStorage = read('lib/core/licensing/license_storage.dart');

    expect(policy, contains('CommercialEntitlementPolicy'));
    expect(policy, contains('server remains the commercial source of truth'));
    expect(legacyTrial, contains('SERVER_AUTHORITY_REQUIRED'));
    expect(legacyTrial, isNot(contains('SharedPreferences')));
    expect(legacyStorage, contains('SERVER_AUTHORITY_REQUIRED'));
    expect(legacyStorage, isNot(contains('SharedPreferences')));
  });
}
