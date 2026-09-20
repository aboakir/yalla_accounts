import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_deposit_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_trace_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String dbPath;
  late Database db;
  late dynamic session;
  late int clientId;
  late int arId;
  late int revenueId;
  late int bankId;
  late bool sessionEnded;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cheque_matrix_');
    dbPath = '${temp.path}/test.db';
    db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'matrix-owner');
    await db.update(
      'owner_bootstrap_state',
      {
        'status': 'COMPLETED',
        'owner_user_id': 'matrix-owner',
        'completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
    sessionEnded = false;

    clientId = await db.insert('clients', {
      'name': 'Matrix Customer',
      'type': 'individual',
    });
    arId = await db.insert('accounts', {
      'code': '1200.C$clientId',
      'name': 'Matrix AR',
      'type': 'ASSET',
      'normal_balance': 'DEBIT',
    });
    await db.update(
      'clients',
      {'account_id': arId},
      where: 'id=?',
      whereArgs: [clientId],
    );
    revenueId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['4000'],
      limit: 1,
    ))
        .single['id'] as int;
    bankId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1010'],
      limit: 1,
    ))
        .single['id'] as int;
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (!sessionEnded) {
      await session.endEphemeralPreviewSession();
    }
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  Future<void> createRepair(String id, double amount) async {
    await db.insert('repairs', {
      'id': id,
      'client_id': clientId,
      'fileValue': amount,
      'paidAmount': 0.0,
      'total_paid_amount': 0.0,
      'paymentStatus': 'غير مسدد',
      'status': 'APPROVED',
      'receivedDate': '2026-09-19T00:00:00',
    });
    await db.insert('invoices', {
      'id': 'INV-$id',
      'repair_id': id,
      'client_id': clientId,
      'date': '2026-09-19',
      'total': amount,
      'paid': 0.0,
      'status': 'UNPAID',
    });
    await db.update(
      'repairs',
      {'invoice_id': 'INV-$id'},
      where: 'id=?',
      whereArgs: [id],
    );
    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 9, 19),
      source: 'INVOICE',
      sourceId: 'INV-$id',
      lines: [
        {
          'account_id': arId,
          'debit': amount,
          'credit': 0.0,
          'party_type': 'CLIENT',
          'party_id': clientId,
          'repair_id': id,
          'invoice_id': 'INV-$id',
        },
        {
          'account_id': revenueId,
          'debit': 0.0,
          'credit': amount,
          'repair_id': id,
          'invoice_id': 'INV-$id',
        },
      ],
    );
  }

  Future<int> receiveAndCollect(String suffix) async {
    final repairId = 'R-$suffix';
    await createRepair(repairId, 3000);
    final receipt = await PaymentService.insertCanonicalReceiptWithInstruments(
      operationId: 'RCV-$suffix',
      database: db,
      clientId: clientId,
      customerName: 'Matrix Customer',
      date: DateTime(2026, 9, 19),
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: 'matrix-$suffix',
          method: 'cheque',
          amount: 3000,
          chequeDraft: {
            'uuid': 'uuid-$suffix',
            'instrument_key': 'matrix-$suffix',
            'cheque_no': 'M-$suffix',
            'drawer_name': 'Matrix Customer',
            'bank_name': 'Drawer Bank',
            'bank_branch': 'Bethlehem',
            'issue_date': '2026-09-19T00:00:00',
            'due_date': '2026-09-25T00:00:00',
          },
          allocations: [
            ReceiptAllocationInput(repairId: repairId, amount: 3000),
          ],
        ),
      ],
    );
    final cheque = (await db.query(
      'cheques',
      where: 'receipt_voucher_id=?',
      whereArgs: [receipt.receiptNumber],
      limit: 1,
    ))
        .single;
    final chequeId = cheque['id'] as int;

    await ChequeDepositService.depositBatch(
      batchId: 'BATCH-$suffix',
      bankAccountId: bankId,
      chequeIds: [chequeId],
      depositDate: DateTime(2026, 9, 20),
      database: db,
    );
    await ChequeAccountingService.transitionStatus(
      chequeId: chequeId,
      newStatus: ChequeStatus.collected,
      eventDate: DateTime(2026, 9, 21),
    );
    return chequeId;
  }

  test('GL-001 every cheque accounting transaction is balanced', () async {
    final chequeId = await receiveAndCollect('GL1');
    final rows = await db.rawQuery(
      '''
      SELECT e.id,
        COALESCE(SUM(l.debit),0) d,
        COALESCE(SUM(l.credit),0) c
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      WHERE l.cheque_id=?
         OR e.id=(SELECT gl_entry_id FROM cheques WHERE id=?)
      GROUP BY e.id
      ORDER BY e.id
      ''',
      [chequeId, chequeId],
    );
    expect(rows.length, greaterThanOrEqualTo(2));
    for (final row in rows) {
      expect(
        (row['d'] as num).toDouble(),
        (row['c'] as num).toDouble(),
        reason: 'GL entry ${row['id']}',
      );
    }
  });

  test('GL-002 lifecycle retry does not duplicate posting', () async {
    final chequeId = await receiveAndCollect('GL2');
    await ChequeAccountingService.transitionStatus(
      chequeId: chequeId,
      newStatus: ChequeStatus.collected,
      eventDate: DateTime(2026, 9, 21),
    );
    final rows = await db.query(
      'gl_entries',
      where: 'source=? AND source_id=?',
      whereArgs: ['CHEQUE_STATUS', '$chequeId:collected'],
    );
    expect(rows, hasLength(1));
    final events = await db.query(
      'cheque_events',
      where: 'cheque_id=? AND event_type=?',
      whereArgs: [chequeId, 'status:collected'],
    );
    expect(events, hasLength(1));
  });

  test('GL-003 trace resolves Cheque to Voucher to Allocation to GL', () async {
    final chequeId = await receiveAndCollect('GL3');
    final trace = await ChequeTraceService.load(chequeId, executor: db);
    expect(trace.voucherLinks, hasLength(1));
    expect(trace.voucherLinks.single['voucher_type'], 'RECEIPT');
    expect(trace.allocations, hasLength(1));
    expect(trace.allocations.single['allocation_type'], 'REPAIR');
    expect(trace.glEntries, isNotEmpty);
    expect(
      trace.glEntries.map((e) => e['source']),
      containsAll(<Object?>['PAYMENT', 'CHEQUE_STATUS']),
    );
    expect(
        trace.events.map((e) => e['event_type']), contains('status:collected'));
  });
  test('PERSIST-001 restart preserves cheque lifecycle and trace links',
      () async {
    final chequeId = await receiveAndCollect('PERSIST');
    final before = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
    ))
        .single;
    expect(before['status'], 'collected');

    await session.endEphemeralPreviewSession();
    sessionEnded = true;
    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();

    db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
    DatabaseMigration.useDatabaseForTesting(db);

    final after = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
    ))
        .single;
    expect(after['status'], 'collected');
    expect(after['collection_date'], isNotNull);
    expect(
      await db.query(
        'cheque_voucher_links',
        where: 'cheque_id=?',
        whereArgs: [chequeId],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'cheque_allocations',
        where: 'cheque_id=?',
        whereArgs: [chequeId],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['CHEQUE_STATUS', '$chequeId:collected'],
      ),
      hasLength(1),
    );
  });
}
