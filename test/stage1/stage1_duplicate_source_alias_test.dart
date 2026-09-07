import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';

Future<Database> _db(String path) async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
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
            reference_id TEXT,
            reference_type TEXT,
            created_at TEXT
          );
        ''');
      },
    ),
  );
}

List<Map<String, Object?>> _lines(double amount) => [
      {
        'account_id': 1,
        'debit': amount,
        'credit': 0.0,
        'party_type': 'SUPPLIER',
        'party_id': 'S0007',
      },
      {
        'account_id': 2,
        'debit': 0.0,
        'credit': amount,
      },
    ];

void main() {
  test('Stage1 PURCHASE_INVOICE and PURCHASE are one accounting identity',
      () async {
    final temp = await Directory.systemTemp.createTemp('yalla_stage1_alias_');
    final db = await _db('${temp.path}/db.sqlite');
    try {
      final first = await AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 7),
        source: 'PURCHASE_INVOICE',
        sourceId: 'P-1',
        lines: _lines(1500),
      );
      final second = await AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 7),
        source: 'PURCHASE',
        sourceId: 'P-1',
        lines: _lines(1500),
      );

      expect(second, first);
      final heads = await db.query('gl_entries');
      expect(heads, hasLength(1));
      expect(heads.single['source'], 'PURCHASE');
      final partyLine = (await db.query(
        'gl_lines',
        where: 'party_type IS NOT NULL',
        limit: 1,
      ))
          .single;
      expect(partyLine['party_id'], '7');
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('Stage1 alias retry with different money fails closed', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_stage1_alias2_');
    final db = await _db('${temp.path}/db.sqlite');
    try {
      await AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 7),
        source: 'PURCHASE_INVOICE',
        sourceId: 'P-2',
        lines: _lines(1500),
      );
      await expectLater(
        AccountingTables.postEntryGLOn(
          ex: db,
          date: DateTime(2026, 9, 7),
          source: 'PURCHASE',
          sourceId: 'P-2',
          lines: _lines(1600),
        ),
        throwsA(isA<StateError>()),
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
