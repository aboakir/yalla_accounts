import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('named desktop intake route never blindly pops after save', () {
    final source = File(
      'lib/features/repairs/screens/add_repair_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("ModalRoute.of(context)?.settings.name"),
    );
    expect(
      source,
      contains('Navigator.of(context).pop(repairId)'),
      reason: 'Unnamed child routes should still return to their caller.',
    );
    expect(
      source,
      contains('pushReplacementNamed(AppRoutes.repairsList)'),
      reason:
          'Named sidebar routes must land on the repairs list after creation.',
    );
  });
}
