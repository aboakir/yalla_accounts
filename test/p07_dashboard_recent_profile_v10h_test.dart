import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard recent files use canonical repair thumbnail', () {
    final source = File(
      'lib/features/home/screens/dashboard_screen.dart',
    ).readAsStringSync();

    expect(source, contains('DBService.getRepairThumbnailPath(repair.id)'));
    expect(source, contains('File(profilePath).existsSync()'));
    expect(source, contains('Image.file('));
    expect(source, contains('Icons.directions_car_filled_rounded'));
  });
}
