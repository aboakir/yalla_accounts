import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YA-HUMAN-004 repair notes show only user-entered notes', () {
    final source = File(
      'lib/features/repairs/screens/repair_details_screen.dart',
    ).readAsStringSync();

    final getterStart = source.indexOf('String get _visibleNotes');
    final getterEnd = source.indexOf('String _formatHistoryDate', getterStart);
    expect(getterStart, greaterThanOrEqualTo(0));
    expect(getterEnd, greaterThan(getterStart));
    final getter = source.substring(getterStart, getterEnd);

    expect(getter, contains('_repair.notes'));
    expect(getter, contains("!line.startsWith('[YALLA_')"));
    expect(getter, isNot(contains('_repairWorks')));
    expect(getter, isNot(contains('_repairParts')));
    expect(source, contains('لا توجد ملاحظات مسجلة.'));
  });

  test('YA-HUMAN-007 vehicle arrears respects iOS safe header', () {
    final source = File(
      'lib/features/repairs/screens/vehicles_arrears_screen.dart',
    ).readAsStringSync();

    expect(source, contains('appBar: AppBar('));
    expect(source, contains("title: const Text('💳 ذمم المركبات'"));
    expect(source, contains("debugPrint('Vehicle arrears load failed:"));
    expect(
      source,
      isNot(contains("_error = e.toString()")),
    );
  });

  test('YA-HUMAN-010 employee dashboard actions are visible and functional',
      () {
    final source = File(
      'lib/features/employees/screens/employee_dashboard_screen.dart',
    ).readAsStringSync();

    expect(source, contains("label: const Text('قائمة الموظفين')"));
    expect(source, contains('builder: (_) => const EmployeesListScreen()'));
    expect(source, contains("label: const Text('إضافة موظف')"));
    expect(source, contains('builder: (_) => const AddEmployeeScreen()'));
    expect(
      RegExp(r'foregroundColor:\s*Colors\.white').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
  });
}
