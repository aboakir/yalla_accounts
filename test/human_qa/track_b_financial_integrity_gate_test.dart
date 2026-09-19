import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/services/accounts_receivable_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FIN-E2E repair receipt requires a posted financial document', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('track_b_doc_guard_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'track-b-owner');
    try {
      final clientId = await db.insert('clients', {
        'name': 'Track B Customer',
        'type': 'individual',
      });
      await db.insert('repairs', {
        'id': 'R-NO-POSTED-DOC',
        'client_id': clientId,
        'fileValue': 1000.0,
        'status': 'APPROVED',
        'receivedDate': '2026-09-19T00:00:00',
        'beneficiaryName': 'Track B Customer',
      });
      final repair = Repair.fromMap(
        (await db.query(
          'repairs',
          where: 'id=?',
          whereArgs: ['R-NO-POSTED-DOC'],
        ))
            .single,
      );
      final beforePayments =
          (await db.rawQuery('SELECT COUNT(*) n FROM payments')).single['n'];
      final beforeGl = (await db.rawQuery(
        "SELECT COUNT(*) n FROM gl_entries WHERE source='PAYMENT'",
      ))
          .single['n'];
      await expectLater(
        AccountsReceivableService.instance.recordPayment(
          repair: repair,
          amount: 100,
          method: 'cash',
        ),
        throwsStateError,
      );

      expect(
        (await db.rawQuery('SELECT COUNT(*) n FROM payments')).single['n'],
        beforePayments,
      );
      expect(
        (await db.rawQuery(
          "SELECT COUNT(*) n FROM gl_entries WHERE source='PAYMENT'",
        ))
            .single['n'],
        beforeGl,
      );
      expect(
        await db.query(
          'invoices',
          where: 'repair_id=?',
          whereArgs: ['R-NO-POSTED-DOC'],
        ),
        isEmpty,
      );
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('FIN-E2E unallocated customer receipt remains explicit credit', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('track_b_credit_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    final session = await startAccountingSession(db, 'track-b-owner');
    try {
      final clientId = await db.insert('clients', {
        'name': 'Credit Customer',
        'type': 'individual',
      });
      final result = await PaymentService.insertCanonicalReceipt(
        operationId: 'TRACK-B-CREDIT-1',
        database: db,
        clientId: clientId,
        customerName: 'Credit Customer',
        method: 'cash',
        date: DateTime(2026, 9, 19),
        allocations: const [],
        unallocatedAmount: 100,
      );
      expect(result.allocatedAmount, 0);
      expect(result.customerCredit, 100);
      expect(await db.query('invoices'), isEmpty);
      final allocations = await db.query(
        'receipt_allocations',
        where: 'receipt_number=?',
        whereArgs: [result.receiptNumber],
      );
      expect(allocations, hasLength(1));
      expect(allocations.single['allocation_type'], 'CREDIT');
      final unbalanced = await db.rawQuery('''
        SELECT e.id
        FROM gl_entries e
        JOIN gl_lines l ON l.entry_id=e.id
        GROUP BY e.id
        HAVING ABS(SUM(l.debit-l.credit)) > 0.001
      ''');
      expect(unbalanced, isEmpty);
    } finally {
      await session.endEphemeralPreviewSession();
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('purchase details cannot mutate the date of a posted invoice', () {
    final source = File(
      'lib/features/finance/purchases/screens/purchase_details_screen.dart',
    ).readAsStringSync();
    expect(source, contains("h['gl_entry_id'] == null"));
    expect(source, contains("if (h['gl_entry_id'] != null)"));
    expect(source, contains('لا يمكن تغيير تاريخ فاتورة مُرحّلة'));
  });
}
