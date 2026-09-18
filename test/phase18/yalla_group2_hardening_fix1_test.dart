import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test(
      'Group 2 workshop settings canonical schema includes owner-bootstrap fields',
      () {
    final userTables = read('lib/core/services/db/tables/user_tables.dart');
    final migration = read('lib/core/services/db/database_migration.dart');
    for (final field in ['address', 'city', 'phone1', 'phone2', 'email']) {
      expect(userTables.contains("'$field': 'TEXT'"), isTrue, reason: field);
    }
    expect(
      migration.contains('UserTables.ensureWorkshopSettingsCompatibility(db)'),
      isTrue,
    );
  });

  test('Group 2 posted invoice update and delete fail closed', () {
    final source = read(
      'lib/features/finance/invoices/services/invoice_service.dart',
    );
    expect(source.contains('_assertInvoiceMutable('), isTrue);
    expect(
      RegExp(r'await _assertInvoiceMutable\(txn, id\);')
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(1),
    );
    expect(source.contains('FinancialVoidService.voidInvoice('), isTrue);
    expect(
        source.contains('RepairAutoAccountingService.deleteRepair('), isTrue);
    expect(source.contains("txn.delete('invoices'"), isFalse);
  });

  test('Group 2 mobile shell exposes truthful sync strip', () {
    final source = read(
      'lib/core/widgets/mobile/yalla_mobile_bottom_nav.dart',
    );
    expect(source.contains('const YallaSyncStatusStrip()'), isTrue);
  });

  test('Group 2 current presentation surfaces do not hardcode shekel symbol',
      () {
    for (final path in [
      'lib/features/home/screens/dashboard_screen.dart',
      'lib/features/home/services/p03_home_service.dart',
      'lib/features/repairs/screens/add_repair_screen.dart',
      'lib/features/repairs/services/edit_repair_service.dart',
    ]) {
      expect(read(path).contains('₪'), isFalse, reason: path);
    }
  });

  test('Group 2 archived migration validators never open canonical live DB',
      () {
    for (final path in [
      'test/commercial/p1_005_live_posting_validate_test.dart',
      'test/commercial/p1_006_live_gl_metadata_validate_test.dart',
      'test/commercial/p1_007_live_coa_validate_test.dart',
    ]) {
      final source = read(path);
      expect(source.contains('DatabaseConstants.dbFilePath()'), isFalse,
          reason: path);
    }
  });
}
