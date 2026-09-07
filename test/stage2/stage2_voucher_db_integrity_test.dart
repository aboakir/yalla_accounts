import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/voucher_tables.dart';

void main() {
  test(
      'Stage2 posted vouchers are immutable but reversible metadata can change',
      () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('yalla_stage2_voucher_');
    final db = await databaseFactoryFfi.openDatabase('${temp.path}/db.sqlite');
    try {
      await VoucherTables.createAllTables(db);

      await db.insert('vouchers', {
        'id': 'V-1',
        'voucher_type': 'PAYMENT',
        'voucher_number': 'P-0001',
        'party_type': 'SUPPLIER',
        'party_id': '1',
        'amount': 1500.0,
        'currency': 'ILS',
        'date': '2026-09-07',
        'method': 'CASH',
        'gl_entry_id': 10,
        'is_posted': 1,
        'status': 'POSTED',
      });

      await expectLater(
        db.update(
          'vouchers',
          {'amount': 1600.0},
          where: 'id=?',
          whereArgs: ['V-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );

      await expectLater(
        db.delete(
          'vouchers',
          where: 'id=?',
          whereArgs: ['V-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        await db.update(
          'vouchers',
          {
            'status': 'REVERSED',
            'reversal_gl_entry_id': 11,
            'reversal_reason': 'test reversal',
          },
          where: 'id=?',
          whereArgs: ['V-1'],
        ),
        1,
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('Stage2 legacy voucher rebuild preserves source linkage', () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('yalla_stage2_legacy_');
    final db = await databaseFactoryFfi.openDatabase('${temp.path}/db.sqlite');
    try {
      await db.execute('''
        CREATE TABLE vouchers (
          id TEXT PRIMARY KEY,
          client_type TEXT,
          voucher_type TEXT,
          voucher_number TEXT,
          voucher_code TEXT,
          party_type TEXT,
          party_id TEXT,
          amount REAL,
          currency TEXT,
          date TEXT,
          method TEXT,
          cheque_id TEXT,
          reference TEXT,
          source TEXT,
          source_id TEXT,
          gl_entry_id INTEGER,
          is_posted INTEGER,
          posted_by TEXT,
          posted_at TEXT,
          notes TEXT,
          attachments TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      await db.insert('vouchers', {
        'id': 'V-LEGACY',
        'client_type': 'old',
        'voucher_type': 'PAYMENT',
        'voucher_number': 'P-0099',
        'party_type': 'SUPPLIER',
        'party_id': '7',
        'amount': 250.0,
        'currency': 'ILS',
        'date': '2026-09-01',
        'method': 'CASH',
        'reference': 'PI-7',
        'source': 'PURCHASE',
        'source_id': 'PI-7',
        'is_posted': 0,
      });

      await VoucherTables.createAllTables(db);

      final rows = await db.query(
        'vouchers',
        where: 'id=?',
        whereArgs: ['V-LEGACY'],
        limit: 1,
      );
      expect(rows, hasLength(1));
      expect(rows.first['source'], 'PURCHASE');
      expect(rows.first['source_id'], 'PI-7');

      final info = await db.rawQuery('PRAGMA table_info(vouchers)');
      final columns = info.map((e) => e['name']).toSet();
      expect(columns.contains('client_type'), isFalse);
      expect(columns.contains('status'), isTrue);
      expect(columns.contains('reversal_reason'), isTrue);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
