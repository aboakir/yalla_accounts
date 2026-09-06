import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C01 FIX8 compact drawer uses stable navigator before navigation', () {
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

    expect(nav, contains('final compactNavigation = !context.isDesktopWidth;'));
    expect(nav, contains('final drawerNavigator = Navigator.of(context);'));
    expect(nav, contains('rootNavigator: compactNavigation'));
    expect(nav, contains('drawerNavigator.pop();'));
    expect(nav, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(nav, contains('if (!targetNavigator.mounted)'));
    expect(nav, contains('targetNavigator.pushNamedAndRemoveUntil('));
    expect(nav, contains('targetNavigator.pushReplacementNamed(route)'));
  });
}
