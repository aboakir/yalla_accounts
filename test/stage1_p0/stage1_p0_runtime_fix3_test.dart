import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('P0-01 phone repair image uses bounded shared image cache', () {
    final details = read(
      'lib/features/repairs/screens/repair_details_screen.dart',
    );
    final thumb = read(
      'lib/features/repairs/widgets/repair_thumb.dart',
    );
    final storedImage = read(
      'lib/core/storage/yalla_stored_image.dart',
    );

    expect(details, contains('RepairThumb('));
    expect(thumb, contains('YallaStoredImage('));
    expect(storedImage, contains('effectiveCacheWidth'));
    expect(storedImage, contains('effectiveCacheHeight'));
    expect(storedImage, contains('clamp(64, 2048)'));
    expect(storedImage, contains('cacheWidth: effectiveCacheWidth'));
    expect(storedImage, contains('cacheHeight: effectiveCacheHeight'));
  });

  test('P0-04 phone attendance has a dedicated id-based mobile body', () {
    final source = read(
      'lib/features/employees/screens/attendance_screen.dart',
    );

    expect(source, contains('STAGE1_RUNTIME_FIX3_ATTENDANCE_PHONE_RECOVERY'));
    expect(source, contains('STAGE1_RUNTIME_FIX3B_ATTENDANCE_PHONE_SAFE_BODY'));
    expect(
      source,
      contains(
        'Widget _buildPhoneAttendanceRuntimeSafe({required EmployeeState empState})',
      ),
    );
    expect(source, contains('DropdownButtonFormField<String>'));
    expect(source, contains('final byId = <String, Employee>{'));
    expect(source, contains('if (isPhone)'));
    expect(
      source,
      contains('return _buildPhoneAttendanceRuntimeSafe(empState: empState)'),
    );
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
