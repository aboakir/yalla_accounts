import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('C01 FIX3D removes the iPhone Arabic mojibake regression', () {
    final sidebar = read('lib/core/widgets/sidebar/yalla_sidebar.dart');

    for (final label in <String>[
      'لوحة التحكم',
      'إصلاح المركبات',
      'وكيل التأمين',
      'السندات المالية',
      'شؤون الموظفين',
      'المشتريات',
      'العملاء والموردون',
      'المالية',
      'الشيكات',
      'الإعدادات',
      'تسجيل خروج',
    ]) {
      expect(sidebar, contains(label));
    }

    for (final bad in <String>[
      'ط§',
      'ظ„',
      'ط¥',
      'ظ…',
      'ًں',
      'â€”',
      'آ·',
    ]) {
      expect(sidebar, isNot(contains(bad)));
    }
  });

  test('C01 FIX3D formats Home dates before RTL presentation', () {
    final service = read('lib/features/home/services/p03_home_service.dart');

    expect(service, contains('static String _displayDate(Object? value)'));
    expect(service, contains(r"return '$day-$month-${parsed.year}';"));
    expect(service,
        contains("final received = _displayDate(row['receivedDate']);"));
    expect(
      service,
      contains(
          "final due = _displayDate(_firstText(row, const ['due_date', 'date']));"),
    );
    expect(service,
        contains("const ['updated_at', 'created_at', 'receivedDate']"));
  });

  test('C01 FIX3D removes the phone repair-card mojibake separator', () {
    final repairs = read('lib/features/repairs/screens/repairs_screen.dart');
    expect(repairs, isNot(contains('آ·')));
    expect(repairs, contains(' · '));
  });
}
