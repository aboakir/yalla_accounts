import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('QA-SAFE-001 live DB paths fail before any database opening', () async {
    final live = ['D:', 'Yallah Accounts', 'yalla_accounts.db'].join('/');
    await expectLater(
        DatabaseMigration.initDatabase(pathOverride: live),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'safety', contains('TEST_DATABASE_SAFETY'))));
  });
  test('QA-SAFE-002 traversal and case variants cannot bypass the guard', () {
    for (final location in [
      ['D:', 'temporary', '..', 'YALLAH ACCOUNTS', 'anything.db'].join('/'),
      ['d:', 'YallaAccounts', 'other.db'].join('/'),
    ]) {
      expect(() => DatabaseConstants.assertSafeTestPath(location),
          throwsStateError);
    }
  });
  test('QA-SAFE-003 temporary database paths are permitted', () {
    expect(
        () => DatabaseConstants.assertSafeTestPath(
            '${Directory.systemTemp.path}/yallah_qa_only/test.db'),
        returnsNormally);
  });
}
