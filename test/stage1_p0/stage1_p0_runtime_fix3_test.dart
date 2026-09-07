import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('P0-01 phone repair image uses finite cache dimensions', () {
    final source = read(
      'lib/features/repairs/screens/repair_details_screen.dart',
    );

    expect(source, contains('STAGE1_RUNTIME_FIX3_REPAIR_IMAGE_CACHE'));
    expect(source, contains('cacheWidth: 1400'));
    expect(source, contains('cacheHeight: 700'));
  });

  test('P0-04 phone attendance has a dedicated id-based mobile body', () {
    final source = read(
      'lib/features/employees/screens/attendance_screen.dart',
    );

    expect(source, contains('STAGE1_RUNTIME_FIX3_ATTENDANCE_PHONE_RECOVERY'));
    expect(source, contains('Widget _buildPhoneAttendance('));
    expect(source, contains('DropdownButtonFormField<String>'));
    expect(source, contains("final byId = <String, Employee>{}"));
    expect(source, contains('YallaBreakpoints.phone'));
  });

  test('P0-05 purchase PDF supplies the five cells expected by generator', () {
    final source = read(
      'lib/features/finance/purchases/screens/purchase_details_screen.dart',
    );

    expect(source, contains('STAGE1_RUNTIME_FIX3_PURCHASE_PDF_COLUMNS'));
    expect(
        source,
        contains(
            "final purchaseCategory = _typeLabel(h['purchase_type']?.toString())"));
    expect(source, contains('purchaseCategory,'));
  });
}
