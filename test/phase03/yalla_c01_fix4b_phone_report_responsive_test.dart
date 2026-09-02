import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('C01 FIX4B keeps Repair Reports axes PHONE-safe', () {
    final reports = read(
      'lib/features/repairs/screens/repair_reports_screen.dart',
    );

    expect(reports, contains("import 'dart:ui' as ui;"));
    expect(reports, contains('textDirection: ui.TextDirection.ltr'));
    expect(reports, contains('rightTitles: const AxisTitles('));
    expect(reports, contains('topTitles: const AxisTitles('));
    expect(reports, contains('SideTitles(showTitles: false)'));
    expect(reports, contains('reservedSize: phone ? 58 : 68'));
    expect(reports, contains('_compactAxisValue(value)'));
    expect(reports, contains('softWrap: false'));
    expect(reports, contains('FittedBox('));
    expect(reports, contains('child: ClipRect('));
    expect(reports, isNot(contains('clipData:')));
    expect(
      reports,
      isNot(contains(
        'leftTitles: const AxisTitles(\n                                sideTitles: SideTitles(showTitles: true)',
      )),
    );
  });

  test('C01 FIX4B does not regress FIX3D Arabic/date presentation', () {
    final sidebar = read('lib/core/widgets/sidebar/yalla_sidebar.dart');
    final home = read('lib/features/home/services/p03_home_service.dart');
    final repairs = read('lib/features/repairs/screens/repairs_screen.dart');

    for (final label in <String>[
      'لوحة التحكم',
      'إصلاح المركبات',
      'المالية',
      'الشيكات',
      'الإعدادات',
    ]) {
      expect(sidebar, contains(label));
    }
    for (final bad in <String>['ط§', 'ظ„', 'ط¥', 'ًں', 'â€”']) {
      expect(sidebar, isNot(contains(bad)));
    }

    expect(home, contains('static String _displayDate(Object? value)'));
    expect(home, contains(r"return '$day-$month-${parsed.year}';"));
    expect(
        home, contains("final received = _displayDate(row['receivedDate']);"));
    expect(repairs, isNot(contains('آ·')));
  });

  test('C01 FIX4B keeps P04 blocked until iPhone PASS', () {
    final state = read('docs/execution/YALLA_PROJECT_STATE.json');
    expect(state, contains('"last_completed_phase": "P03"'));
    expect(state, contains('"current_phase": "C01"'));
    expect(state, contains('"P04": "PENDING"'));
    expect(state, contains('"C01": "RETEST_PENDING"'));
    expect(state, contains('"human_retest": "PENDING"'));
  });
}
