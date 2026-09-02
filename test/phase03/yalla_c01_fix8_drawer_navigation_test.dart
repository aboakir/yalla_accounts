import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C01 FIX8 compact drawer closes from drawer context before navigation',
      () {
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

    final nav = source.substring(
      start.start,
      start.start + end!.start,
    );

    expect(nav, contains('final navigator = Navigator.of(context);'));
    expect(nav, contains('scaffoldState?.isDrawerOpen == true'));
    expect(nav, contains('scaffoldState?.isEndDrawerOpen == true'));
    expect(nav, contains('final compactNavigation = !context.isDesktopWidth;'));

    final compactBranch = nav.indexOf('if (compactNavigation) {');
    final pop = nav.indexOf('navigator.pop();', compactBranch);
    final delay = nav.indexOf(
      'await Future<void>.delayed(const Duration(milliseconds: 320));',
      pop,
    );
    final navigatorMounted =
        nav.indexOf('if (!navigator.mounted) return;', delay);
    final replace = nav.indexOf('navigator.pushReplacementNamed(route)', delay);

    expect(compactBranch, greaterThanOrEqualTo(0));
    expect(pop, greaterThan(compactBranch));
    expect(delay, greaterThan(pop));
    expect(navigatorMounted, greaterThan(delay));
    expect(replace, greaterThan(navigatorMounted));

    // A sidebar-State mounted gate after navigator.pop() would abort routing
    // when the Drawer subtree is disposed during its close animation.
    final staleMountedGate = nav.indexOf('if (!mounted) return;', pop);
    expect(
      staleMountedGate,
      equals(-1),
      reason:
          'Do not gate the post-drawer route replacement on YallaSidebar.mounted.',
    );

    expect(
        nav, isNot(contains('WidgetsBinding.instance.addPostFrameCallback')));
  });
}
