import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C01 FIX5B compact drawer closes before route replacement', () {
    final file = File('lib/core/widgets/sidebar/yalla_sidebar.dart');
    expect(file.existsSync(), isTrue, reason: 'Sidebar source must exist.');

    final source = file.readAsStringSync();
    final startMatch = RegExp(
      r'(?:Future\s*<\s*void\s*>|void)\s+_navigate\s*\(\s*String\s+route\s*\)\s*async\s*\{',
      multiLine: true,
    ).firstMatch(source);
    expect(startMatch, isNotNull, reason: '_navigate method must exist.');

    final start = startMatch!.start;
    final endMatch = RegExp(
      r'Future\s*<\s*void\s*>\s+_navigateAddParty\s*\(\s*\)',
      multiLine: true,
    ).firstMatch(source.substring(start));
    expect(endMatch, isNotNull,
        reason: '_navigateAddParty boundary must exist.');

    final end = start + endMatch!.start;
    final nav = source.substring(start, end);

    expect(nav, contains('scaffoldState?.closeDrawer();'));
    expect(nav, contains('scaffoldState?.closeEndDrawer();'));
    expect(nav, contains('navigator.pushReplacementNamed(route)'));
    expect(nav, contains('Duration(milliseconds: 280)'));
    expect(
      nav,
      isNot(contains('WidgetsBinding.instance.addPostFrameCallback')),
      reason:
          'Drawer navigation must not depend on the drawer State surviving.',
    );

    expect(source, contains('rRepairsDashboard'));
    expect(source, contains('rVehiclesList'));
  });
}
