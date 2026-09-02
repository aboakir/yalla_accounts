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

    expect(
      RegExp(
        r"if\s*\(\s*MediaQuery\.sizeOf\(context\)\.width\s*>=\s*600\s*\)\s*"
        r"const\s+YallaSidebar\s*\(\s*currentRoute:\s*'/vehicles_list'\s*\)",
        multiLine: true,
      ).hasMatch(vehicles),
      isTrue,
      reason:
          'VehiclesListScreen must not embed its legacy sidebar on phone widths.',
    );

    final frameOwnNavStart =
        frame.indexOf('bool get _screenAlreadyOwnsPhoneNav');
    expect(frameOwnNavStart, greaterThanOrEqualTo(0));
    final frameBuildStart = frame.indexOf('@override', frameOwnNavStart);
    expect(frameBuildStart, greaterThan(frameOwnNavStart));
    final ownNavBlock = frame.substring(frameOwnNavStart, frameBuildStart);

    expect(ownNavBlock, contains('AppRoutes.repairsDashboard'));
    expect(
      ownNavBlock,
      isNot(contains('AppRoutes.vehiclesList')),
      reason:
          'Vehicles list must remain wrapped by the global phone route frame.',
    );

    expect(
      frame,
      contains('if (MediaQuery.sizeOf(context).width >= 600) return child;'),
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
