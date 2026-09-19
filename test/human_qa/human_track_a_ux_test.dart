import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/theme/yalla_button_themes.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_theme.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/support/screens/technical_support_screen.dart';

void main() {
  test('UX-BTN-001..003 shared primary buttons keep readable states', () {
    final styles = [
      YallaButtonThemes.elevated.style!,
      YallaButtonThemes.filled.style!,
    ];
    for (final style in styles) {
      expect(style.backgroundColor!.resolve({}), AppColors.primary);
      expect(style.foregroundColor!.resolve({}), Colors.white);
      expect(
        style.backgroundColor!.resolve({MaterialState.disabled}),
        isNot(style.foregroundColor!.resolve({MaterialState.disabled})),
      );
    }
  });

  test('UX-BTN-004..006 employee labels remain visible in RTL actions', () {
    final details = File(
      'lib/features/employees/screens/employee_details_screen.dart',
    ).readAsStringSync();
    final add = File(
      'lib/features/employees/screens/add_employee_screen.dart',
    ).readAsStringSync();
    final edit = File(
      'lib/features/employees/screens/edit_employee_screen.dart',
    ).readAsStringSync();
    expect(details, contains('تعديل البيانات العامة'));
    expect(details, contains('تعديل الراتب'));
    expect(add, contains('حفظ نهائي'));
    expect(edit, contains('حفظ التعديلات'));
    expect(YallaButtonThemes.elevated.style!.foregroundColor!.resolve({}),
        Colors.white);
  });

  test('NAV-001/002/008 compact drawer width is stable and never full screen',
      () {
    for (var i = 0; i < 20; i++) {
      expect(YallaSidebar.compactDrawerWidth(390), 300);
      expect(YallaSidebar.compactDrawerWidth(320), closeTo(262.4, .01));
      expect(YallaSidebar.compactDrawerWidth(430), 300);
      expect(YallaSidebar.compactDrawerWidth(390), lessThan(390));
    }
  });

  testWidgets('NAV-001..008 drawer opens repeatedly without width drift',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(
        child: _DrawerHarness(),
      ),
    );
    final state =
        tester.state<ScaffoldState>(find.byKey(_DrawerHarness.scaffoldKey));
    for (var i = 0; i < 20; i++) {
      state.openDrawer();
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(YallaSidebar)).width,
          lessThanOrEqualTo(300));
      expect(find.text('غير مفعّل حاليًا'), findsNothing);
      state.closeDrawer();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  test('NAV-003/005/006/007 hidden features have no dead presentation', () {
    final source = File(
      'lib/core/widgets/sidebar/yalla_sidebar.dart',
    ).readAsStringSync();
    expect(source, contains('SafeArea('));
    expect(source, contains('isInsuranceAgentFrozenRoute(route)'));
    expect(source, contains(r'_isRouteVisible(e.$3)'));
    expect(source, contains('ReleaseScopeConfig.chequesEnabled'));
    expect(source, contains('ReleaseScopeConfig.employeeAdvancesEnabled'));
    expect(source, isNot(contains('غير مفعّل حاليًا')));
    expect(source,
        contains('if (children.isEmpty) return const SizedBox.shrink()'));
    expect(source, contains('showToggle: context.isDesktopWidth'));
  });

  test('ROUTE-001..004 repair analytics resolves to its own screen', () {
    final route = AppRoutes.onGenerateRoute(
      const RouteSettings(name: AppRoutes.repairAnalytics),
    );
    expect(route.settings.name, AppRoutes.repairAnalytics);
    final routes = File('lib/core/routes/app_routes.dart').readAsStringSync();
    final analytics = File(
      'lib/features/repairs/screens/repair_analytics_screen.dart',
    ).readAsStringSync();
    expect(routes, contains('const RepairAnalyticsScreen()'));
    expect(analytics, contains('تحليلات إصلاح المركبات'));
    expect(AppRoutes.repairAnalytics, isNot(AppRoutes.vehiclesArrears));
  });

  test('MEDIA-001..006 image policy uses real media and safe thumbnails', () {
    final vehicleService = File(
      'lib/features/vehicles/services/vehicle_service.dart',
    ).readAsStringSync();
    final vehicles = File(
      'lib/features/repairs/screens/vehicles_list_screen.dart',
    ).readAsStringSync();
    final repairs = File(
      'lib/features/repairs/screens/repairs_screen.dart',
    ).readAsStringSync();
    final storedImage = File(
      'lib/core/storage/yalla_stored_image.dart',
    ).readAsStringSync();
    expect(vehicleService, contains('repair.thumbnailPath'));
    expect(vehicleService, contains('...repair.imagePaths'));
    expect(vehicleService, contains('resolveExistingPath(candidate)'));
    expect(vehicles, contains('width: 64'));
    expect(repairs, contains('width: 72'));
    expect(storedImage, contains('fit = BoxFit.cover'));
    expect(storedImage, contains('errorBuilder:'));
  });

  test('RTL-001..005 contact numbers keep canonical LTR values', () {
    expect(
      TechnicalSupportScreen.canonicalPhone('+970 566 061 666'),
      '+970566061666',
    );
    expect(
      TechnicalSupportScreen.canonicalPhone('0594 680 857'),
      '0594680857',
    );
    expect(
      TechnicalSupportScreen.whatsappUri('+970 566 061 666').toString(),
      'https://wa.me/970566061666',
    );
    expect(
      TechnicalSupportScreen.phoneUri('0594 680 857').toString(),
      'tel:0594680857',
    );
    final source = File(
      'lib/features/support/screens/technical_support_screen.dart',
    ).readAsStringSync();
    expect(source, contains('textDirection: TextDirection.ltr'));
    expect(source, contains('ClipboardData(text: canonical)'));
  });
}

class _DrawerHarness extends StatelessWidget {
  const _DrawerHarness();

  static const scaffoldKey = Key('track-a-drawer-scaffold');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: YallaMobileTheme.from(
        ThemeData(useMaterial3: true),
        viewportWidth: 390,
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          key: scaffoldKey,
          drawer: const Drawer(child: YallaSidebar()),
          body: const SizedBox.expand(),
        ),
      ),
    );
  }
}
