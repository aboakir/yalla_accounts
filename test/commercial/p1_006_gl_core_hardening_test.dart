import '../support/accounting_session.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/posting_engine.dart';

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('P1.006 fresh current DB posts metadata and creates linked reversal',
      () async {
    SharedPreferences.setMockInitialValues({});

    final temp = await Directory.systemTemp.createTemp('yalla_p1_006_');
    final path = '${temp.path}${Platform.pathSeparator}fresh.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    final session = await startAccountingSession(db, 'audit-user');

    try {
      expect(firstInt(await db.rawQuery('PRAGMA user_version')),
          DatabaseConstants.dbVersion);
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(61));

      final accountRows = await db.query(
        'accounts',
        columns: ['id', 'code'],
        where: 'code IN (?, ?)',
        whereArgs: ['1000', '4000'],
      );
      final byCode = {
        for (final row in accountRows)
          row['code'].toString(): (row['id'] as num).toInt(),
      };

      final originalId = await PostingEngine.postEntryOn(
        ex: db,
        date: DateTime(2026, 8, 19),
        ref: 'DOC-0001',
        source: 'TEST_DOC',
        sourceId: 'test-doc-1',
        sourceNumber: 'DOC-0001',
        lines: [
          {
            'account_id': byCode['1000'],
            'debit': 100.0,
            'credit': 0.0,
          },
          {
            'account_id': byCode['4000'],
            'debit': 0.0,
            'credit': 100.0,
          },
        ],
      );

      final original = (await db.query(
        'gl_entries',
        where: 'id=?',
        whereArgs: [originalId],
        limit: 1,
      ))
          .single;

      expect(original['source_number'], 'DOC-0001');
      expect((original['posting_version'] as num).toInt(), 1);
      expect(original['created_by'], 'audit-user');
      expect(original['created_at'], isNotNull);
      expect(original['reversal_of'], isNull);

      final reversalId = await PostingEngine.reverseEntryOn(
        db,
        originalId,
        note: 'test reversal',
      );

      final reversal = (await db.query(
        'gl_entries',
        where: 'id=?',
        whereArgs: [reversalId],
        limit: 1,
      ))
          .single;

      expect((reversal['reversal_of'] as num).toInt(), originalId);
      expect(reversal['source_id'], 'GLREV:$originalId');
      expect(reversal['source_number'], 'DOC-0001-REV');
      expect(reversal['created_by'], 'audit-user');

      await expectLater(
        PostingEngine.reverseEntryOn(db, originalId),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        db.update(
          'gl_entries',
          {'note': 'illegal mutation'},
          where: 'id=?',
          whereArgs: [originalId],
        ),
        throwsA(isA<DatabaseException>()),
      );

      final lineId = firstInt(await db.rawQuery(
        'SELECT MIN(id) FROM gl_lines WHERE entry_id=?',
        [originalId],
      ));

      await expectLater(
        db.delete(
          'gl_lines',
          where: 'id=?',
          whereArgs: [lineId],
        ),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await session.endEphemeralPreviewSession();
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.006 does not fabricate unknown historical actor/timestamps', () {
    final source = File(
      'lib/core/services/db/tables/accounting_tables.dart',
    ).readAsStringSync();

    expect(source.contains('SET created_by ='), isFalse);
    expect(source.contains('SET created_at = date'), isFalse);
  });
}
