import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    DatabaseMigration.useDatabaseForTesting(null);
  });
  test(
    'bundled migration fixtures open read-only without WAL sidecars',
    () async {
      for (final entry in {'commercial83': 83, 'owner78': 78}.entries) {
        final bytes = gzip.decode(
          await File(
            'test/fixtures/migration/${entry.key}.db.gz',
          ).readAsBytes(),
        );
        expect(
          bytes.sublist(18, 20),
          [1, 1],
          reason: 'Standalone fixtures must use rollback-journal format',
        );
        final directory = await Directory.systemTemp.createTemp(
          'portable_lineage_',
        );
        final dbPath = '${directory.path}/fixture.db';
        await File(dbPath).writeAsBytes(bytes, flush: true);
        Database? db;
        try {
          expect(await File('$dbPath-wal').exists(), isFalse);
          expect(await File('$dbPath-shm').exists(), isFalse);
          db = await databaseFactoryFfi.openDatabase(
            dbPath,
            options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
          );
          expect(await db.getVersion(), entry.value);
          expect(
            (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
            'ok',
          );
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          if (db != null && db.isOpen) await db.close();
          await directory.delete(recursive: true);
        }
      }
    },
  );

  for (final lineage in ['commercial83', 'owner78']) {
    test(
      'v84 upgrades authentic $lineage without changing financial facts',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'yallah_lineage_',
        );
        final dbPath = '${directory.path}/fixture.db';
        final fixture = 'test/fixtures/migration/$lineage';
        await File(
          dbPath,
        ).writeAsBytes(gzip.decode(await File('$fixture.db.gz').readAsBytes()));
        final before =
            jsonDecode(await File('$fixture.json').readAsString())
                as Map<String, dynamic>;
        Database? db;
        try {
          db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
          expect(await db.getVersion(), 84);
          expect(DatabaseConstants.dbVersion, 84);
          for (final table in ['clients', 'gl_entries', 'gl_lines']) {
            final expected = (before[table] as List)
                .cast<Map<String, dynamic>>();
            final actual = await db.query(table, orderBy: 'id');
            expect(
              actual.length,
              expected.length,
              reason: '$lineage $table row count',
            );
            for (var i = 0; i < expected.length; i++) {
              for (final field in expected[i].entries) {
                expect(
                  actual[i][field.key],
                  field.value,
                  reason: '$lineage $table ${field.key}',
                );
              }
            }
          }
          final cheques = await db.query('cheques', orderBy: 'id');
          final oldCheques = before['cheques'] as List;
          expect(cheques.length, oldCheques.length);
          for (var i = 0; i < cheques.length; i++) {
            for (final field in [
              'id',
              'uuid',
              'cheque_no',
              'amount',
              'currency',
              'client_id',
              'issue_date',
              'due_date',
            ]) {
              expect(
                cheques[i][field],
                oldCheques[i][field],
                reason: '$lineage cheque $field',
              );
            }
          }
          final names = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'",
          )).map((r) => r['name']).toSet();
          for (final name in [
            'sync_outbox',
            'sync_inbox',
            'cheque_books',
            'cheque_allocations',
            'receipt_instruments',
            'inventory_movements',
          ]) {
            expect(names, contains(name), reason: '$lineage missing $name');
          }
          final parties = await db.rawQuery('PRAGMA table_info(parties)');
          expect(parties.any((c) => c['name'] == 'role_codes'), isTrue);
          final context = await db.rawQuery(
            'PRAGMA table_info(sync_mutation_context)',
          );
          expect(context.any((c) => c['name'] == 'remote_revision'), isTrue);
          final features = await db.query('schema_feature_migrations');
          expect(features.length, 4);
          expect(
            features.every((r) => r['from_schema_version'] == before['schema']),
            isTrue,
          );
          expect(
            (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
            'ok',
          );
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
          final financialBeforeRestart = await db.query(
            'gl_lines',
            orderBy: 'id',
          );
          await db.close();
          DatabaseMigration.useDatabaseForTesting(null);
          db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
          expect(
            await db.query('gl_lines', orderBy: 'id'),
            financialBeforeRestart,
          );
          expect(await db.query('schema_feature_migrations'), features);
        } finally {
          DatabaseMigration.useDatabaseForTesting(null);
          if (db != null && db.isOpen) await db.close();
          await directory.delete(recursive: true);
        }
      },
    );
  }
  test(
    'v84 refuses a future schema without downgrading or resetting data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yallah_future_schema_',
      );
      final dbPath = '${directory.path}/fixture.db';
      await File(dbPath).writeAsBytes(
        gzip.decode(
          await File(
            'test/fixtures/migration/commercial83.db.gz',
          ).readAsBytes(),
        ),
      );
      try {
        var db = await databaseFactoryFfi.openDatabase(dbPath);
        await db.setVersion(85);
        final before = await db.query('gl_lines', orderBy: 'id');
        await db.close();
        await expectLater(
          DatabaseMigration.initDatabase(pathOverride: dbPath),
          throwsA(isA<StateError>()),
        );
        db = await databaseFactoryFfi.openDatabase(dbPath);
        expect(await db.getVersion(), 85);
        expect(await db.query('gl_lines', orderBy: 'id'), before);
        await db.close();
      } finally {
        DatabaseMigration.useDatabaseForTesting(null);
        await directory.delete(recursive: true);
      }
    },
  );
}
