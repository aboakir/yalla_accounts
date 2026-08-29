import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';

Future<Database> _openTestDb(String path) async {
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
            note TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        ''');

        await db.execute(
          'CREATE UNIQUE INDEX uq_gl_source '
          'ON gl_entries(source, source_id)',
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
          )
        ''');
      },
    ),
  );
}

int _firstIntValue(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, Object?>> _invoiceLines(double amount) => [
      {
        'account_id': 10,
        'debit': amount,
        'credit': 0.0,
        'party_type': 'CLIENT',
        'party_id': '3',
        'invoice_id': 'INV-1',
        'repair_id': 'REP-1',
      },
      {
        'account_id': 20,
        'debit': 0.0,
        'credit': amount,
        'party_type': null,
        'party_id': null,
        'invoice_id': 'INV-1',
        'repair_id': 'REP-1',
      },
    ];

void main() {
  test('P0.001 same posting is idempotent, including after reopen', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_p0_001_');
    final dbPath = '${temp.path}${Platform.pathSeparator}posting_test.db';

    var db = await _openTestDb(dbPath);

    final first = await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 8, 18),
      source: 'INVOICE',
      sourceId: 'INV-1',
      lines: _invoiceLines(2200),
    );

    final second = await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 8, 18),
      source: 'INVOICE',
      sourceId: 'INV-1',
      lines: _invoiceLines(2200),
    );

    expect(second, first);
    expect(
      _firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM gl_lines WHERE entry_id = ?',
          [first],
        ),
      ),
      2,
    );

    await db.close();
    db = await _openTestDb(dbPath);

    final afterReopen = await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 8, 18),
      source: 'INVOICE',
      sourceId: 'INV-1',
      lines: _invoiceLines(2200),
    );

    expect(afterReopen, first);
    expect(
      _firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM gl_lines WHERE entry_id = ?',
          [first],
        ),
      ),
      2,
    );

    await db.close();
    await temp.delete(recursive: true);
  });

  test('P0.001 same source key with different money fails closed', () async {
    final temp =
        await Directory.systemTemp.createTemp('yalla_p0_001_conflict_');
    final dbPath = '${temp.path}${Platform.pathSeparator}posting_test.db';
    final db = await _openTestDb(dbPath);

    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 8, 18),
      source: 'INVOICE',
      sourceId: 'INV-1',
      lines: _invoiceLines(2200),
    );

    await expectLater(
      AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 8, 18),
        source: 'INVOICE',
        sourceId: 'INV-1',
        lines: _invoiceLines(3200),
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      _firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM gl_lines'),
      ),
      2,
    );

    await db.close();
    await temp.delete(recursive: true);
  });
}
