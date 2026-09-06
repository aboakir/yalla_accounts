import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';

void main() {
  test(
    'P1.005 archived live-v60 certification is not run against the current customer DB',
    () {
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(69));

      final self = File(
        'test/commercial/p1_005_live_posting_validate_test.dart',
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
