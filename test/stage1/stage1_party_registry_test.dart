import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';

void main() {
  test('Stage1 one Party can own customer and supplier roles', () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('yalla_stage1_party_');
    final db = await databaseFactoryFfi.openDatabase('${temp.path}/db.sqlite');
    try {
      await db.execute(
        'CREATE TABLE clients(id INTEGER PRIMARY KEY, name TEXT NOT NULL);',
      );
      await db.execute(
        'CREATE TABLE suppliers(id INTEGER PRIMARY KEY, name TEXT NOT NULL);',
      );
      await db.execute('''
        CREATE TABLE employees(
          id TEXT PRIMARY KEY,
          full_name TEXT NOT NULL
        );
      ''');
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
          reference_type TEXT
        );
      ''');

      await db.insert('clients', {'id': 10, 'name': 'نواورة'});
      await db.insert('suppliers', {'id': 20, 'name': 'نواورة'});
      await PartyTables.ensure(db);

      final customerParty = await PartyTables.resolvePartyId(
        db,
        role: 'CUSTOMER',
        legacyId: 10,
      );
      final supplierParty = await PartyTables.resolvePartyId(
        db,
        role: 'SUPPLIER',
        legacyId: 20,
      );
      expect(customerParty, isNotNull);
      expect(supplierParty, isNot(customerParty));

      await PartyTables.attachRoleToParty(
        db,
        targetPartyId: customerParty!,
        role: 'SUPPLIER',
        legacyId: 20,
      );
      expect(
        await PartyTables.resolvePartyId(
          db,
          role: 'SUPPLIER',
          legacyId: 20,
        ),
        customerParty,
      );

      await db.insert('gl_lines', {
        'entry_id': 1,
        'account_id': 101,
        'debit': 1500.0,
        'credit': 0.0,
        'party_type': 'CLIENT',
        'party_id': '10',
      });
      await db.insert('gl_lines', {
        'entry_id': 2,
        'account_id': 202,
        'debit': 0.0,
        'credit': 900.0,
        'party_type': 'SUPPLIER',
        'party_id': 'S0020',
      });
      final balance = (await db.query(
        'v_party_balances',
        where: 'party_id=?',
        whereArgs: [customerParty],
      ))
          .single;
      expect((balance['receivable_balance'] as num).toDouble(), 1500.0);
      expect((balance['payable_balance'] as num).toDouble(), 900.0);
      expect((balance['net_position'] as num).toDouble(), 600.0);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
