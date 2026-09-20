import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_encryption_service.dart';
import 'package:yalla_accounts/core/services/db/database_startup_recovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String target;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('yallah_hot_recovery_');
    target = '${temp.path}/subject.db';
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<void> installHotFixture() async {
    for (final suffix in ['', '-journal']) {
      final data = await File('test/fixtures/recovery/hot_journal.db$suffix.gz')
          .readAsBytes();
      await File('$target$suffix').writeAsBytes(gzip.decode(data), flush: true);
    }
  }

  Future<Database> openRecovery() => databaseFactoryFfi.openDatabase(target,
      options: OpenDatabaseOptions(readOnly: false, singleInstance: false));
  test(
      'a hot journal blocks read-only probing; engine recovery preserves committed rows',
      () async {
    await installHotFixture();
    Future<void> readonlyProbe() async {
      Database? db;
      try {
        db = await DatabaseEncryptionService.openReadOnlyCandidate(target);
        await db.rawQuery('SELECT COUNT(*) FROM recovery_sentinel');
      } finally {
        if (db != null && db.isOpen) await db.close();
      }
    }

    await expectLater(readonlyProbe(), throwsA(anything));
    expect(await File('$target-journal').exists(), isTrue);
    expect(
        await DatabaseEncryptionService.recoverInterruptedCanonicalWrite(
            target),
        isTrue);
    final db = await DatabaseEncryptionService.openReadOnlyCandidate(target);
    try {
      expect(await db.getVersion(), 7);
      final rows = await db.query('recovery_sentinel', orderBy: 'id');
      expect(rows.length, 80);
      expect(rows.every((r) => (r['value'] as String).startsWith('committed-')),
          isTrue);
      expect((await db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok');
    } finally {
      await db.close();
    }
    expect(
        await DatabaseStartupRecovery.recoverIfNeeded(target,
            openWithoutMigration: openRecovery),
        isFalse);
  });
  test(
      'no file or no journal never invokes an opener or creates a new database',
      () async {
    var calls = 0;
    Future<Database> opener() {
      calls++;
      throw StateError('must not open');
    }

    expect(
        await DatabaseStartupRecovery.recoverIfNeeded(target,
            openWithoutMigration: opener),
        isFalse);
    expect(await File(target).exists(), isFalse);
    await File(target).writeAsBytes([1, 2, 3]);
    expect(
        await DatabaseStartupRecovery.recoverIfNeeded(target,
            openWithoutMigration: opener),
        isFalse);
    expect(calls, 0);
  });
  test('opening/key failures preserve both files byte for byte', () async {
    await installHotFixture();
    final databaseBytes = await File(target).readAsBytes();
    final journalBytes = await File('$target-journal').readAsBytes();
    await expectLater(
        DatabaseStartupRecovery.recoverIfNeeded(target,
            openWithoutMigration: () async =>
                throw StateError('installation key unavailable')),
        throwsA(isA<StateError>()));
    expect(await File(target).readAsBytes(), databaseBytes);
    expect(await File('$target-journal').readAsBytes(), journalBytes);
  });
  test(
      'recovery precedes the readonly version probe, backup validation stays readonly',
      () {
    final migration =
        File('lib/core/services/db/database_migration.dart').readAsStringSync();
    final encryption =
        File('lib/core/services/db/database_encryption_service.dart')
            .readAsStringSync();
    final init = migration
        .substring(migration.indexOf('static Future<Database> initDatabase'));
    expect(init.indexOf('recoverInterruptedCanonicalWrite(path)'),
        lessThan(init.indexOf('await _readExistingVersion(')));
    final recovery = encryption.substring(
        encryption.indexOf('recoverInterruptedCanonicalWrite('),
        encryption.indexOf('static Future<DatabaseEncryptionPreparation?>'));
    expect(recovery, contains('DatabaseEncryptionKeyStore.readExisting()'));
    expect(recovery, isNot(contains('readOrCreate')));
    expect(recovery, isNot(contains('.delete(')));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.indexOf('runApp(const _BootstrapLoadingApp())'),
        lessThan(main.indexOf('await _bootstrap();')));
    expect(main, isNot(contains('DBService.database.timeout(')));
  });
}
