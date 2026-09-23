import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/accounting_integrity_service.dart';
import 'package:yalla_accounts/core/services/accounting_period_service.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('global accounting period close blocks every GL gateway atomically',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('final_period_close_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'period.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'final-period-owner');

    try {
      Future<int> account(String code) async {
        final rows = await db.query(
          'accounts',
          columns: const ['id'],
          where: 'code=?',
          whereArgs: [code],
          limit: 1,
        );
        return (rows.single['id'] as num).toInt();
      }

      final cash = await account('1000');
      final bank = await account('1010');

      await DBService.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 10),
        source: 'FINAL_PRE_CLOSE',
        sourceId: 'PRE-1',
        createdBy: 'final-period-owner',
        lines: [
          {'account_id': cash, 'debit': 100.0, 'credit': 0.0},
          {'account_id': bank, 'debit': 0.0, 'credit': 100.0},
        ],
      );

      expect((await AccountingIntegrityService.healthReportOn(db))['healthy'],
          isTrue);

      final closeId = await AccountingPeriodService.closePeriod(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
        note: 'Final commercial acceptance close',
        database: db,
      );
      expect(closeId, greaterThan(0));
      expect(
        await AccountingPeriodService.isClosed(
          DateTime(2026, 9, 15),
          database: db,
        ),
        isTrue,
      );

      final before = ((await db.rawQuery(
        'SELECT COUNT(*) AS n FROM gl_entries',
      ))
              .single['n'] as num)
          .toInt();

      await expectLater(
        DBService.postEntryGLOn(
          ex: db,
          date: DateTime(2026, 9, 15),
          source: 'FINAL_CLOSED_POST',
          sourceId: 'BLOCK-1',
          createdBy: 'final-period-owner',
          lines: [
            {'account_id': cash, 'debit': 50.0, 'credit': 0.0},
            {'account_id': bank, 'debit': 0.0, 'credit': 50.0},
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            contains('ACCOUNTING_PERIOD_CLOSED'),
          ),
        ),
      );
      expect(
        ((await db.rawQuery(
          'SELECT COUNT(*) AS n FROM gl_entries',
        ))
                .single['n'] as num)
            .toInt(),
        before,
      );

      await expectLater(
        AccountingTables.stageSyncedGlEntryOn(
          ex: db,
          date: DateTime(2026, 9, 20),
          source: 'SYNC',
          sourceId: 'SYNC-CLOSED',
          createdBy: 'final-period-owner',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            contains('ACCOUNTING_PERIOD_CLOSED'),
          ),
        ),
      );

      await DBService.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 10, 1),
        source: 'FINAL_NEXT_PERIOD',
        sourceId: 'OCT-1',
        createdBy: 'final-period-owner',
        lines: [
          {'account_id': cash, 'debit': 25.0, 'credit': 0.0},
          {'account_id': bank, 'debit': 0.0, 'credit': 25.0},
        ],
      );

      await AccountingPeriodService.reopenPeriod(
        closeId,
        reason: 'Acceptance reopen proof',
        database: db,
      );
      expect(
        await AccountingPeriodService.isClosed(
          DateTime(2026, 9, 15),
          database: db,
        ),
        isFalse,
      );

      await DBService.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 25),
        source: 'FINAL_REOPENED_POST',
        sourceId: 'REOPEN-1',
        createdBy: 'final-period-owner',
        lines: [
          {'account_id': cash, 'debit': 10.0, 'credit': 0.0},
          {'account_id': bank, 'debit': 0.0, 'credit': 10.0},
        ],
      );

      final events = await AccountingPeriodService.events(
        closeId,
        database: db,
      );
      expect(events.map((e) => e['action']), ['CLOSE', 'REOPEN']);
      await AccountingIntegrityService.assertHealthyOn(db);
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}
