import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
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

    expect(sidebar, contains('rootNavigator: true'));
    expect(sidebar, contains('targetNavigator.pushNamed(route)'));
    expect(sidebar, isNot(contains('targetNavigator.pushReplacementNamed(route)')));
    expect(sidebar, isNot(contains('pushNamedAndRemoveUntil(')));
    expect(bottom, contains('rootNavigator: true'));
    expect(bottom, contains('pushNamed(route)'));
    expect(bottom, isNot(contains('pushReplacementNamed(route)')));
    expect(bottom, isNot(contains('pushNamedAndRemoveUntil(route')));
  });

  test('ROOT-ISSUE-NAV-001 startup creates one route with no hidden splash',
      () {
    final routes = AppRoutes.generateInitialRoutes(AppRoutes.startup);

    expect(routes, hasLength(1));
    expect(routes.single.settings.name, AppRoutes.startup);

    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(
      mainSource,
      contains('onGenerateInitialRoutes: AppRoutes.generateInitialRoutes'),
    );
  });

  testWidgets(
      'ROOT-ISSUE-NAV-001 bottom tab Back returns to dashboard, never bootstrap',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('BOOTSTRAP')),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(
            body: Center(child: Text('TARGET:${settings.name}')),
          ),
        ),
      ),
    ));

    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: AppRoutes.dashboard),
      builder: (_) => Scaffold(
        body: Column(
          children: [
            const Text('DASHBOARD'),
            YallaMobileBottomNav(
              currentRoute: AppRoutes.dashboard,
              onMore: () {},
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.car_repair_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text('TARGET:${AppRoutes.repairsDashboard}'),
      findsOneWidget,
    );

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('BOOTSTRAP'), findsNothing);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
      'ROOT-ISSUE-NAV-001 root Back falls back to dashboard, never blank',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      initialRoute: '/orphan',
      onGenerateInitialRoutes: (initialRoute) => <Route<dynamic>>[
        MaterialPageRoute<void>(
          settings: RouteSettings(name: initialRoute),
          builder: (_) => Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => AppRoutes.popOrDashboard(context),
                child: const Text('BACK'),
              ),
            ),
          ),
        ),
      ],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(
          body: Center(child: Text('ROUTE:${settings.name}')),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();

    expect(find.text('ROUTE:${AppRoutes.dashboard}'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
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
