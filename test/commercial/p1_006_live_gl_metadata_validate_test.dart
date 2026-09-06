import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';

void main() {
  test(
    'P1.006 archived v60-to-v61 migration remains present without opening live DB',
    () {
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(69));

      final migration = File(
        'lib/core/services/db/tables/accounting_tables.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'oldV\s*<\s*61').hasMatch(migration),
        isTrue,
        reason: 'Historical v60→v61 migration path must remain available.',
      );

      final self = File(
        'test/commercial/p1_006_live_gl_metadata_validate_test.dart',
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
