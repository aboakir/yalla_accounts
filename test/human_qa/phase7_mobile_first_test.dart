import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YA-HUMAN-018 owner reports use compact phone grid', () {
    final source = File(
      'lib/features/reports/screens/reports_dashboard_screen.dart',
    ).readAsStringSync();
    expect(source, contains('final columns = width < 600'));
    expect(source, contains('? 2'));
    expect(source, contains('GridView.count('));
    expect(source, contains('shrinkWrap: true'));
  });

  test('YA-HUMAN-019 trial balance uses mobile cards and valid drawer context',
      () {
    final source = File(
      'lib/features/reports/screens/trial_balance_screen.dart',
    ).readAsStringSync();
    expect(source,
        contains('!Responsive.isDesktop(context) ? _cards() : _table()'));
    expect(source, contains('builder: (menuContext) => IconButton('));
    expect(source, contains('Scaffold.of(menuContext).openDrawer()'));
    expect(source, isNot(contains('_error = e.toString()')));
  });

  test('YA-HUMAN-020 general ledger never forces desktop table on phone', () {
    final source = File(
      'lib/features/reports/screens/general_ledger_screen.dart',
    ).readAsStringSync();
    expect(source, contains('isMobile'));
    expect(source, contains('? _GLCards('));
    expect(source, contains("label: const Text('القيد والمستند')"));
    expect(source, contains('Scaffold.of(menuContext).openDrawer()'));
    expect(source, isNot(contains("setState(() => _error = e.toString())")));
  });

  test('YA-HUMAN-022 cheque dashboard uses two phone columns', () {
    final source = File(
      'lib/features/cheques/screens/cheques_dashboard_screen.dart',
    ).readAsStringSync();
    expect(source, contains('final grid = viewportWidth >= 1024'));
    expect(source, contains(': 2;'));
    expect(source, contains('GridView.count('));
    expect(source, isNot(contains('خطأ في تحميل الشيكات')));
  });

  test(
      'YA-HUMAN-023 cheque lists use mobile cards and collapsed advanced filters',
      () {
    final source = File(
      'lib/features/cheques/screens/cheques_list_screen.dart',
    ).readAsStringSync();
    expect(source, contains(': _buildCards(list);'));
    expect(source, contains('bool _showAdvancedFilters = false;'));
    expect(source, contains("'فلاتر متقدمة'"));
    expect(source, contains('if (showAdvanced) ...['));
  });

  test('YA-HUMAN-026 cheque report is mobile-first', () {
    final source = File(
      'lib/features/cheques/screens/cheques_report_screen.dart',
    ).readAsStringSync();
    expect(source, contains('bool _showAdvancedFilters = false;'));
    expect(source, contains('if (context.isPhoneWidth) ...['));
    expect(source, contains("if (context.isPhoneWidth) return table;"));
    expect(source, contains('AdaptiveDataTable('));
  });
}
