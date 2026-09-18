import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repair intake returns to its caller and only falls back at route root',
      () {
    final source = File(
      'lib/features/repairs/screens/add_repair_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final navigator = Navigator.of(context);'));
    expect(
      source,
      contains('if (navigator.canPop())'),
      reason:
          'A repair opened above the existing list must return to that caller.',
    );
    expect(
      source,
      contains('navigator.pop(repairId)'),
      reason: 'The caller receives the created repair id and can refresh.',
    );
    expect(
      source,
      contains('navigator.pushReplacementNamed(AppRoutes.repairsList)'),
      reason:
          'A true route root still has a safe fallback to the repairs list.',
    );
    expect(
      source,
      isNot(contains("ModalRoute.of(context)?.settings.name")),
      reason: 'Route naming must not force a second guarded route after save.',
    );
  });
}
