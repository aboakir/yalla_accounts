import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/reports/providers/ar_aging_provider.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AR2-001 aging keeps customer overpayment as negative credit balance',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('ar2_credit_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'ar2-owner');
    try {
      final clientId = await db.insert('clients', {
        'name': 'AR credit customer',
        'type': 'individual',
      });
      final arId = await db.insert('accounts', {
        'code': '1200.C$clientId',
        'name': 'AR credit customer',
        'type': 'ASSET',
        'normal_balance': 'DEBIT',
      });
      final revenueId = (await db.query(
        'accounts',
        columns: const ['id'],
        where: 'code=?',
        whereArgs: const ['4000'],
        limit: 1,
      ))
          .single['id'] as int;
      final cashId = (await db.query(
        'accounts',
        columns: const ['id'],
        where: 'code=?',
        whereArgs: const ['1000'],
        limit: 1,
      ))
          .single['id'] as int;
      await AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 1),
        source: 'INVOICE',
        sourceId: 'AR2-INV-1',
        createdBy: 'ar2-owner',
        lines: [
          {
            'account_id': arId,
            'debit': 100.0,
            'credit': 0.0,
            'party_type': 'CLIENT',
            'party_id': clientId,
          },
          {
            'account_id': revenueId,
            'debit': 0.0,
            'credit': 100.0,
          },
        ],
      );
      await AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 2),
        source: 'PAYMENT',
        sourceId: 'AR2-RCPT-1',
        createdBy: 'ar2-owner',
        lines: [
          {'account_id': cashId, 'debit': 150.0, 'credit': 0.0},
          {
            'account_id': arId,
            'debit': 0.0,
            'credit': 150.0,
            'party_type': 'CLIENT',
            'party_id': clientId,
          },
        ],
      );
      final rows = await ARAgingProvider.fetch(asOf: DateTime(2026, 9, 30));
      expect(rows, hasLength(1));
      expect(rows.single.clientId, clientId);
      expect(rows.single.balance, -50.0);
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
