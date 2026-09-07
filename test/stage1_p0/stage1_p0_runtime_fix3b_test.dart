import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync();

String _between(String source, String start, String end) {
  final a = source.indexOf(start);
  final b = source.indexOf(end, a + start.length);
  expect(a, greaterThanOrEqualTo(0), reason: 'Missing start marker: $start');
  expect(b, greaterThan(a), reason: 'Missing end marker: $end');
  return source.substring(a, b);
}

void main() {
  test('P0-01 phone repair details uses isolated safe body', () {
    final source = _source(
      'lib/features/repairs/screens/repair_details_screen.dart',
    );

    expect(
      source,
      contains('STAGE1_RUNTIME_FIX3B_REPAIR_PHONE_SAFE_BODY'),
    );
    expect(source, contains('return _buildPhoneDetailsRuntimeSafe('));

    final safeBody = _between(
      source,
      'STAGE1_RUNTIME_FIX3B_REPAIR_PHONE_SAFE_BODY',
      '@override\n  Widget build(BuildContext context)',
    );

    for (final risky in <String>[
      'YallaStoredImage(',
      '_buildImagesStrip(',
      '_buildDataTable(',
      '_buildActionsBar(',
      'RepairProfitabilityCard(',
      '_buildWorkflowCard(',
      '_buildStatusPanel(',
    ]) {
      expect(safeBody, isNot(contains(risky)),
          reason: 'Risky phone child: $risky');
    }

    expect(safeBody, contains("linesCard('أعمال الإصلاح', _repairWorks)"));
    expect(safeBody, contains("linesCard('القطع المطلوبة', _repairParts)"));
    expect(safeBody, contains('_repair.totalFileValue'));
    expect(safeBody, contains('_repair.totalPaidAmount'));
    expect(safeBody, contains('_repair.remainingAmount'));
    expect(safeBody, contains('_repair.beneficiaryName'));
  });

  test('P0-04 phone attendance uses id keyed isolated body', () {
    final source = _source(
      'lib/features/employees/screens/attendance_screen.dart',
    );

    expect(
      source,
      contains('STAGE1_RUNTIME_FIX3B_ATTENDANCE_PHONE_SAFE_BODY'),
    );
    expect(
      source,
      contains('return _buildPhoneAttendanceRuntimeSafe(empState: empState)'),
    );
    expect(source, contains('final user = ref.watch(currentUserProvider);'));

    final safeBody = _between(
      source,
      'STAGE1_RUNTIME_FIX3B_ATTENDANCE_PHONE_SAFE_BODY',
      'Widget _buildPhoneAttendance({',
    );

    expect(safeBody, contains('DropdownButtonFormField<String>'));
    expect(safeBody, contains('employee.id: employee'));
    expect(source, contains('AttendanceDatabaseService'));
    expect(safeBody, contains('await _loadAttendance()'));
    expect(safeBody, isNot(contains('DropdownButtonFormField<Employee>')));
    expect(safeBody, isNot(contains('_buildAppBar(')));
    expect(safeBody, isNot(contains('_buildKPIsBar(')));
    expect(safeBody, isNot(contains('YallaSidebar(')));
  });

  test('P0-05 purchase PDF supplies all five generator cells', () {
    final source = _source(
      'lib/features/finance/purchases/screens/purchase_details_screen.dart',
    );

    expect(source, contains('STAGE1_RUNTIME_FIX3_PURCHASE_PDF_COLUMNS'));
    expect(source, contains('final purchaseCategory = _typeLabel('));

    final pdfBlock = _between(
      source,
      'Future<void> _exportPdf() async',
      '@override\n  Widget build(BuildContext context)',
    );
    expect(pdfBlock, contains('purchaseCategory,'));
    expect(pdfBlock, contains('rows: pdfRows'));
  });
}
