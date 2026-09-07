import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/accounting_integrity_service.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_integrity_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';

void main() {
  test('Stage1 every new GL post has immutable audit trace to its source',
      () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('yalla_stage1_trace_');
    final db = await databaseFactoryFfi.openDatabase('${temp.path}/db.sqlite');
    try {
      await db.execute('''
        CREATE TABLE gl_entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          ref TEXT,
          source TEXT NOT NULL,
          source_id TEXT NOT NULL,
          source_number TEXT,
          posting_version INTEGER NOT NULL DEFAULT 1,
          reversal_of INTEGER,
          created_by TEXT,
          note TEXT,
          created_at TEXT
        );
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX uq_gl_source ON gl_entries(source, source_id);',
      );
      await db.execute('''
        CREATE TABLE gl_lines(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entry_id INTEGER NOT NULL,
          account_id INTEGER NOT NULL,
          debit REAL NOT NULL DEFAULT 0,
          credit REAL NOT NULL DEFAULT 0,
          party_type TEXT,
          party_id TEXT,
          invoice_id TEXT,
          repair_id TEXT,
          cheque_id INTEGER,
          created_at TEXT
        );
      ''');
      await AccountingIntegrityTables.ensure(db);

      final entryId = await AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 7),
        source: 'TEST_DOC',
        sourceId: 'D-1',
        createdBy: 'owner-1',
        lines: [
          {'account_id': 1, 'debit': 100.0, 'credit': 0.0},
          {'account_id': 2, 'debit': 0.0, 'credit': 100.0},
        ],
      );

      final trace = await AccountingIntegrityService.traceSourceOn(
        db,
        source: 'TEST_DOC',
        sourceId: 'D-1',
      );
      expect(trace['posted'], isTrue);
      expect((trace['entry'] as Map)['id'], entryId);
      expect((trace['lines'] as List), hasLength(2));
      expect((trace['audit_events'] as List), hasLength(1));

      await expectLater(
        db.delete(
          'accounting_audit_events',
          where: 'gl_entry_id=?',
          whereArgs: [entryId],
        ),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
