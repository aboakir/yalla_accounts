import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v74 upgrades to v75 costing schema without losing repair data', () {
    final constants =
        File('lib/core/services/db/database_constants.dart').readAsStringSync();
    final migration =
        File('lib/core/services/db/database_migration.dart').readAsStringSync();
    expect(constants, contains('dbVersion = 75'));
    expect(migration, contains('if (oldV < 75) await _upgradeV75(db);'));
    expect(migration, contains('await RepairCostService.ensureSchema(db);'));
    expect(migration, contains("'version': 75"));
    expect(migration, isNot(contains('DROP TABLE repairs')));
    expect(migration, isNot(contains('DELETE FROM repairs')));
  });
}
