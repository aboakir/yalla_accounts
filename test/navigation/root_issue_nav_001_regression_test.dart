import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';

void main() {
  test('ROOT-ISSUE-NAV-001 compact navigation never exposes bootstrap route',
      () {
    final sidebar = File(
      'lib/core/widgets/sidebar/yalla_sidebar.dart',
    ).readAsStringSync();
    final bottom = File(
      'lib/core/widgets/mobile/yalla_mobile_bottom_nav.dart',
    ).readAsStringSync();

    expect(sidebar, contains('? targetNavigator.pushNamed(route)'));
    expect(
      sidebar,
      isNot(contains('? targetNavigator.pushNamedAndRemoveUntil(')),
    );
    expect(bottom, contains('pushReplacementNamed(route)'));
    expect(bottom, isNot(contains('pushNamedAndRemoveUntil(route')));
  });

  testWidgets(
      'ROOT-ISSUE-NAV-001 drawer Back returns to visible previous route',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final navigatorKey = GlobalKey<NavigatorState>();
    final dashboardKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('BOOTSTRAP')),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('TARGET')),
            body: const Text('TARGET BODY'),
          ),
        ),
      ),
    ));

    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: AppRoutes.dashboard),
      builder: (_) => Scaffold(
        key: dashboardKey,
        drawer: const Drawer(
          child: YallaSidebar(currentRoute: AppRoutes.dashboard),
        ),
        body: const Text('DASHBOARD'),
      ),
    ));
    await tester.pumpAndSettle();

    dashboardKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('البحث الشامل'));
    await tester.pumpAndSettle();

    expect(find.text('TARGET BODY'), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('BOOTSTRAP'), findsNothing);

    await tester.binding.setSurfaceSize(null);
  });

  test('ROOT-ISSUE-NAV-001 seven reproduced routes stay registered', () {
    const routes = <String>{
      AppRoutes.globalSearch,
      AppRoutes.repairsAdd,
      AppRoutes.vehiclesArrears,
      AppRoutes.insuranceInvoices,
      AppRoutes.employeeAttendance,
      AppRoutes.parties,
      AppRoutes.partyAdd,
    };
    expect(routes.length, 7);
    for (final route in routes) {
      expect(AppRoutes.isRegisteredRoute(route), isTrue, reason: route);
    }
  });

  test('ROOT-ISSUE-NAV-001 stack pruning is session-lifecycle only', () {
    const allowed = <String>{
      'core/licensing/trial_expired_screen.dart',
      'core/widgets/idle_timeout_wrapper.dart',
      'features/activation/screens/activation_screen.dart',
      'features/auth/screens/account_security_screen.dart',
      'features/auth/screens/forgot_access_screen.dart',
      'features/auth/screens/login_screen.dart',
      'features/auth/screens/logout_screen.dart',
      'features/auth/screens/reset_password_screen.dart',
      'features/auth/screens/user_dashboard_screen.dart',
      'features/auth/screens/yalla_control_center_screen.dart',
      'features/auth/widgets/authenticated_route_gate.dart',
      'features/onboarding/screens/workshop_onboarding_completion_screen.dart',
      'features/onboarding/screens/workshop_onboarding_screen.dart',
      'features/settings/screens/security_data_screen.dart',
    };
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      if (!entity.readAsStringSync().contains('pushNamedAndRemoveUntil')) {
        continue;
      }
      final relative = path.startsWith('lib/')
          ? path.substring(4)
          : path.split('/lib/').last;
      if (!allowed.contains(relative)) {
        offenders.add(relative);
      }
    }
    expect(offenders, isEmpty,
        reason: 'Unsafe non-session stack pruning: ${offenders.join(', ')}');
  });
}
