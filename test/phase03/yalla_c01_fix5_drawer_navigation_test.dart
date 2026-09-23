import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C01 FIX5B compact drawer closes before preserving previous route', () {
    final source = File(
      'lib/core/widgets/sidebar/yalla_sidebar.dart',
    ).readAsStringSync();

    final start = RegExp(
      r'(?:Future\s*<\s*void\s*>|void)\s+_navigate\s*\(\s*String\s+route\s*\)\s*async\s*\{',
    ).firstMatch(source);
    expect(start, isNotNull);

    final end = RegExp(
      r'Future\s*<\s*void\s*>\s+_navigateAddParty\s*\(',
    ).firstMatch(source.substring(start!.start));
    expect(end, isNotNull);

    final nav = source.substring(start.start, start.start + end!.start);

    expect(nav, contains('final drawerNavigator = Navigator.of(context);'));
    expect(nav, contains('final targetNavigator ='));
    expect(nav, contains('scaffoldState?.isDrawerOpen == true'));
    expect(nav, contains('scaffoldState?.isEndDrawerOpen == true'));
    expect(nav, contains('drawerNavigator.pop();'));
    expect(nav, contains('targetNavigator.pushNamed(route)'));
    expect(nav, isNot(contains('targetNavigator.pushNamedAndRemoveUntil(')));
    expect(nav, isNot(contains('targetNavigator.pushReplacementNamed(route)')));
    expect(nav, contains('if (!targetNavigator.mounted)'));

    expect(source, contains('rRepairsDashboard'));
    expect(source, contains('rVehiclesList'));
  });
}
