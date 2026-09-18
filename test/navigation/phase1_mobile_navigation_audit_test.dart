import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_route_frame.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_theme.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';

const _appBar = YallaAppBar(
  workshopName: 'Test',
  showThemeToggle: false,
  showSearch: false,
  showNotifications: false,
  showUserAvatar: false,
);

Future<void> _pumpPhone(
  WidgetTester tester, {
  required String route,
  required Widget child,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: YallaMobileRouteFrame(
            routeName: route,
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _drawerScaffolds() => find.byWidgetPredicate(
      (widget) => widget is Scaffold && widget.drawer != null,
      description: 'Scaffold with drawer',
      skipOffstage: false,
    );

void main() {
  testWidgets('Frame-owned phone route has one drawer and one hamburger',
      (tester) async {
    await _pumpPhone(
      tester,
      route: AppRoutes.payments,
      child: const Scaffold(appBar: _appBar, body: SizedBox()),
    );

    expect(_drawerScaffolds(), findsOneWidget);
    expect(
      find.byKey(const Key('yalla_appbar_mobile_menu_button')),
      findsOneWidget,
    );
  });

  testWidgets('Feature-owned phone route is not wrapped in a second drawer',
      (tester) async {
    await _pumpPhone(
      tester,
      route: AppRoutes.chequesList,
      child: const Scaffold(
        drawer: Drawer(child: SizedBox()),
        appBar: _appBar,
        body: SizedBox(),
      ),
    );

    expect(_drawerScaffolds(), findsOneWidget);
    expect(
      find.byKey(const Key('yalla_appbar_mobile_menu_button')),
      findsOneWidget,
    );
  });

  testWidgets('Frame hamburger opens the single shared drawer', (tester) async {
    await _pumpPhone(
      tester,
      route: AppRoutes.payments,
      child: const Scaffold(appBar: _appBar, body: SizedBox()),
    );
    final scaffold = tester.state<ScaffoldState>(_drawerScaffolds());
    expect(scaffold.isDrawerOpen, isFalse);
    await tester.tap(find.byKey(const Key('yalla_appbar_mobile_menu_button')));
    await tester.pumpAndSettle();
    expect(scaffold.isDrawerOpen, isTrue);
  });

  test('Mobile navigation does not declare endDrawer anywhere', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (RegExp(r'^\s*endDrawer\s*:', multiLine: true).hasMatch(source)) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'endDrawer declarations found: ${offenders.join(', ')}');
  });

  test('Mobile drawer appearance and ownership are centralized', () {
    final mobileTheme = YallaMobileTheme.from(ThemeData());
    final sidebar =
        File('lib/core/widgets/sidebar/yalla_sidebar.dart').readAsStringSync();
    final appBar =
        File('lib/core/widgets/yalla_appbar.dart').readAsStringSync();
    final salary = File('lib/features/employees/screens/salary_screen.dart')
        .readAsStringSync();

    expect(mobileTheme.drawerTheme.width, 300);
    expect(mobileTheme.drawerTheme.shape, isA<RoundedRectangleBorder>());
    expect(sidebar, contains('child: SafeArea('));
    expect(sidebar,
        contains('width: context.isDesktopWidth ? _widthAnim.value : 300'));
    expect(appBar, contains('YallaMobileRouteScope.maybeOf(context)'));
    expect(appBar, contains('mobileRouteScope.openDrawer'));
    expect(salary, isNot(contains('_openSidebarPanel')));
    expect(salary, isNot(contains('showGeneralDialog(')));
  });

  test('Feature-owned finance screens provide their own real drawer', () {
    final gl = File('lib/features/finance/gl/screens/gl_browser_screen.dart')
        .readAsStringSync();
    final aging = File(
            'lib/features/finance/purchases/screens/suppliers_aging_screen.dart')
        .readAsStringSync();
    expect(gl, contains('const Drawer(child: YallaSidebar())'));
    expect(aging, contains('const Drawer(child: YallaSidebar())'));
  });
}
