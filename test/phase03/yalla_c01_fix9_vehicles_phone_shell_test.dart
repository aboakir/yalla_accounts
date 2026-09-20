import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C01 FIX9 vehicles list has exactly one phone navigation shell', () {
    final vehicles = File(
      'lib/features/repairs/screens/vehicles_list_screen.dart',
    ).readAsStringSync();
    final frame = File(
      'lib/core/widgets/mobile/yalla_mobile_route_frame.dart',
    ).readAsStringSync();
    final routes = File(
      'lib/core/routes/app_routes.dart',
    ).readAsStringSync();

    expect(vehicles, contains('if (context.isDesktopWidth)'));
    expect(
      vehicles,
      contains("const YallaSidebar(currentRoute: '/vehicles_list')"),
    );
    expect(
      vehicles,
      contains('MediaQuery.sizeOf(context).width >= 600'),
      reason: 'Phone widths must not directly render the desktop sidebar.',
    );

    final featureRoutesStart =
        frame.indexOf('static const _featureOwnedPhoneRoutes');
    expect(featureRoutesStart, greaterThanOrEqualTo(0));
    final frameOwnNavStart = frame.indexOf(
        'bool get _screenAlreadyOwnsPhoneNav', featureRoutesStart);
    expect(frameOwnNavStart, greaterThan(featureRoutesStart));
    final ownNavBlock = frame.substring(featureRoutesStart, frameOwnNavStart);

    expect(ownNavBlock, contains('AppRoutes.repairsDashboard'));
    expect(
      ownNavBlock,
      isNot(contains('AppRoutes.vehiclesList')),
      reason:
          'Vehicles list must remain wrapped by the global phone route frame.',
    );

    expect(
      frame,
      contains('if (MediaQuery.sizeOf(context).width >= 600) return widget.child;'),
    );
    expect(frame, contains('drawer: Drawer('));
    expect(frame, contains('YallaMobileBottomNav('));

    expect(
      RegExp(
        r'if\s*\(\s*name\s*==\s*vehiclesList\s*\)\s*\{[\s\S]*?'
        r'return\s+_page\s*\(\s*settings\s*,\s*const\s+VehiclesListScreen\s*\(\s*\)\s*\)',
      ).hasMatch(routes),
      isTrue,
      reason:
          'Vehicles list route must continue through _page/YallaMobileRouteFrame.',
    );
  });
}
