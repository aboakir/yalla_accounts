import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_integrity_tables.dart';

void main() {
  test('Stage1 posted purchase is retained and financial fields are immutable',
      () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('yalla_stage1_guard_');
    final db = await databaseFactoryFfi.openDatabase('${temp.path}/db.sqlite');
    try {
      await db.execute('''
        CREATE TABLE gl_entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          source TEXT NOT NULL,
          source_id TEXT NOT NULL,
          source_number TEXT,
          posting_version INTEGER NOT NULL DEFAULT 1,
          reversal_of INTEGER,
          created_by TEXT,
          created_at TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE purchase_invoices(
          id TEXT PRIMARY KEY,
          supplier_id INTEGER,
          date TEXT,
          total REAL,
          amount_total REAL,
          status TEXT,
          updated_at TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE purchase_invoice_lines(
          id TEXT PRIMARY KEY,
          invoice_id TEXT NOT NULL,
          total REAL
        );
      ''');
      await db.insert('purchase_invoices', {
        'id': 'P-1',
        'supplier_id': 1,
        'date': '2026-09-07',
        'total': 1500.0,
        'amount_total': 1500.0,
        'status': 'UNPAID',
      });
      await db.insert('purchase_invoice_lines', {
        'id': 'L-1',
        'invoice_id': 'P-1',
        'total': 1500.0,
      });
      await db.insert('gl_entries', {
        'date': '2026-09-07',
        'source': 'PURCHASE',
        'source_id': 'P-1',
        'created_at': '2026-09-07',
      });

      await AccountingIntegrityTables.ensure(db);

      await expectLater(
        db.update(
          'purchase_invoices',
          {'total': 1600.0},
          where: 'id=?',
          whereArgs: ['P-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.delete(
          'purchase_invoices',
          where: 'id=?',
          whereArgs: ['P-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Operational cancellation/cache state can change without rewriting money.
      expect(
        await db.update(
          'purchase_invoices',
          {'status': 'CANCELLED'},
          where: 'id=?',
          whereArgs: ['P-1'],
        ),
        1,
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
