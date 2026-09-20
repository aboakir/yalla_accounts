import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('P04.1 mobile database encryption contract is fail-closed', () {
    final pubspec = source('pubspec.yaml');
    final migration = source('lib/core/services/db/database_migration.dart');
    final encryption =
        source('lib/core/services/db/database_encryption_service.dart');
    final keys =
        source('lib/core/services/db/database_encryption_key_store.dart');
    final backup = source('lib/core/services/backup_service.dart');
    final constants = source('lib/core/services/db/database_constants.dart');
    final gradle = source('android/app/build.gradle.kts');
    final proguard = source('android/app/proguard-rules.pro');
    final state = source('docs/execution/YALLA_PROJECT_STATE.json');

    expect(pubspec, contains('sqflite_sqlcipher: ^3.4.1'));
    expect(pubspec, contains('sqflite_common_ffi: ^2.3.3'));
    expect(keys, contains('Random.secure()'));
    expect(keys, contains('List<int>.generate(32'));
    expect(keys, contains('FlutterSecureStorage'));
    expect(keys, contains('yalla_accounts.database_key.v1'));
    expect(keys, isNot(contains('debugPrint')));
    expect(keys, isNot(contains('print(')));
    expect(encryption, contains('Platform.isIOS || Platform.isAndroid'));
    expect(encryption, contains('sqlcipher.openDatabase('));
    expect(encryption, contains('password: password'));
    expect(encryption, contains("SELECT sqlcipher_export('encrypted')"));
    expect(encryption, contains('PRAGMA encrypted.user_version'));
    expect(encryption, contains('PRAGMA encrypted.auto_vacuum'));
    expect(encryption, contains('PRAGMA cipher_version'));
    expect(encryption, contains('PRAGMA integrity_check'));
    expect(encryption, contains('PRAGMA foreign_key_check'));
    expect(encryption, contains('_tableCounts'));
    expect(encryption, contains('.p04_plaintext_backup'));
    expect(encryption, contains('.p04_encrypting'));
    expect(encryption, contains('Yallah Accounts will not reset it.'));
    expect(migration,
        contains('DatabaseEncryptionService.prepareCanonical(path)'));
    expect(migration, contains('pathOverride == null'));
    expect(migration, contains('await encryption.open('));
    expect(migration, contains('await encryption?.commit();'));
    expect(migration, contains('await encryption?.rollback();'));
    expect(migration, contains('await openDatabase('));
    expect(backup,
        contains('DatabaseEncryptionService.openReadOnlyCandidate(path)'));
    final version = int.parse(
      RegExp(r'static const int dbVersion = (\d+);')
          .firstMatch(constants)!
          .group(1)!,
    );
    expect(version, greaterThanOrEqualTo(76));
    expect(gradle, contains('"proguard-rules.pro"'));
    expect(proguard, contains('-keep class net.sqlcipher.** { *; }'));
    // P04.1 is a security regression test, not a chronology lock.
    // While P04 is being built the state is IN_PROGRESS; once P04.3 closes
    // the phase it correctly becomes PASS and later phases may become current.
    expect(state, contains('"C01": "PASS"'));
    expect(
      state.contains('"P04": "IN_PROGRESS"') || state.contains('"P04": "PASS"'),
      isTrue,
    );
  });

  test('P04.1 never introduces production reset as encryption fallback', () {
    final encryption =
        source('lib/core/services/db/database_encryption_service.dart');
    final migration = source('lib/core/services/db/database_migration.dart');
    expect(encryption, isNot(contains('resetDatabase(')));
    expect(encryption, isNot(contains('deleteDatabase(')));
    expect(
        encryption, contains('Ambiguous database encryption recovery state'));
    final resetIndex = migration.indexOf('static Future<void> resetDatabase()');
    expect(resetIndex, greaterThanOrEqualTo(0));
    expect(migration.substring(resetIndex), contains('if (!kDebugMode)'));
  });
}
