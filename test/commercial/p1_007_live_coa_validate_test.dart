import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';

void main() {
  test(
    'P1.007 archived v61-to-v62 migration remains present without opening live DB',
    () {
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(69));

      final migration = File(
        'lib/core/services/db/tables/accounting_tables.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'oldV\s*<\s*62').hasMatch(migration),
        isTrue,
        reason: 'Historical v61→v62 migration path must remain available.',
      );

      final self = File(
        'test/commercial/p1_007_live_coa_validate_test.dart',
      ).readAsStringSync();

      final canonicalDbPathCall = 'DatabaseConstants.' 'dbFilePath()';
      final openDbCall = 'open' 'Database(';
      final deleteDbCall = 'delete' 'Database(';

      expect(self.contains(canonicalDbPathCall), isFalse);
      expect(self.contains(openDbCall), isFalse);
      expect(self.contains(deleteDbCall), isFalse);
    },
  );
}
