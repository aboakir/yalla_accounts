import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows database policy prefers D and keeps mobile sandboxed', () {
    final source = File(
      'lib/core/services/db/database_constants.dart',
    ).readAsStringSync();

    expect(source, contains("const preferred = 'D:/Yallah Accounts'"));
    expect(source, contains("_canUseWindowsDirectory(preferred)"));
    expect(source, contains("LOCALAPPDATA"));
    expect(source, contains(r'$base/Yallah Accounts'));
    expect(source, contains("Platform.isIOS || Platform.isAndroid"));
    expect(source, contains("getApplicationSupportDirectory()"));
    expect(source, contains("Nothing is copied or migrated between drives"));
  });

  test('legacy feature services use the canonical DBService connection', () {
    for (final file in const [
      'lib/features/finance/inventory/inventory_service.dart',
      'lib/features/repairs/services/purchase_part_service.dart',
      'lib/features/repairs/screens/edit_repair_screen.dart',
    ]) {
      final source = File(file).readAsStringSync();
      expect(source, contains('DBService.database'), reason: file);
      expect(source, isNot(contains('getDatabasesPath()')), reason: file);
    }
  });
}
