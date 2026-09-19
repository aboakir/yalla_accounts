import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_dashboard_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_trace_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_deposit_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late AuthSessionService ownerSession;
  late int clientId;
  late int supplierId;
  late int bankId;
  late int arId;
  late int incomingId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cheque_center_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    ownerSession = await startAccountingSession(db, 'trace-owner');

    clientId = await db.insert('clients', {
      'name': 'Trace Customer',
      'type': 'individual',
    });
    supplierId = await db.insert('suppliers', {'name': 'Trace Supplier'});
    bankId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1010'],
      limit: 1,
    ))
        .single['id'] as int;
    incomingId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1020'],
      limit: 1,
    ))
        .single['id'] as int;
    arId = await db.insert('accounts', {
      'code': '1200.C$clientId',
      'name': 'Trace Customer AR',
      'type': 'ASSET',
      'normal_balance': 'DEBIT',
    });
    await db.update(
      'clients',
      {'account_id': arId},
      where: 'id=?',
      whereArgs: [clientId],
    );
  });
  tearDown(() async {
    AuthorizationGuard.disableInteractiveEnforcement();
    DatabaseMigration.useDatabaseForTesting(null);
    await ownerSession.endEphemeralPreviewSession();
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<int> buildReceivedTraceCheque() async {
    await db.insert('repairs', {
      'id': 'TRACE-REPAIR',
      'client_id': clientId,
      'vehicleNumber': 'TRACE-VEHICLE',
      'fileValue': 1200.0,
      'status': 'APPROVED',
      'receivedDate': '2026-09-19T00:00:00',
    });
    await db.insert('invoices', {
      'id': 'TRACE-INVOICE',
      'repair_id': 'TRACE-REPAIR',
      'client_id': clientId,
      'date': '2026-09-19',
      'total': 1200.0,
      'status': 'UNPAID',
    });
    await db.insert('receipt_headers', {
      'receipt_number': 7001,
      'client_id': clientId,
      'date': '2026-09-19',
      'method': 'cheque',
      'total_amount': 1200.0,
      'allocated_amount': 1200.0,
      'credit_amount': 0.0,
      'status': 'posted',
      'created_at': '2026-09-19T00:00:00',
    });

    late int chequeId;
    await db.transaction((txn) async {
      chequeId = await ChequeAccountingService.createLinkedChequeOnTxn(
        txn: txn,
        draft: {
          'uuid': 'trace-received-uuid',
          'instrument_key': 'trace-instrument',
          'cheque_no': 'RCV-TRACE-7001',
          'drawer_name': 'Trace Customer',
          'bank_name': 'Trace Drawer Bank',
          'bank_branch': 'Bethlehem',
          'issue_date': '2026-09-19T00:00:00',
          'due_date': '2026-09-25T00:00:00',
        },
        type: ChequeType.incoming,
        amount: 1200,
        currency: 'ILS',
        sourceType: 'RECEIPT',
        sourceId: '7001',
        instrumentKey: 'trace-instrument',
        receiptVoucherId: 7001,
        sourcePartyType: 'CLIENT',
        sourcePartyId: clientId.toString(),
        clientId: clientId,
        recipientType: 'WORKSHOP',
        recipientName: 'Workshop',
        createdBy: 'trace-owner',
      );
      await ChequeAccountingService.linkChequeToVoucherOnTxn(
        txn: txn,
        chequeId: chequeId,
        voucherType: 'RECEIPT',
        voucherId: '7001',
        instrumentKey: 'trace-instrument',
        amount: 1200,
      );
      await ChequeAccountingService.allocateChequeOnTxn(
        txn: txn,
        chequeId: chequeId,
        voucherType: 'RECEIPT',
        voucherId: '7001',
        allocationType: 'REPAIR',
        targetId: 'TRACE-REPAIR',
        amount: 1200,
      );
      final glId = await AccountingTables.postEntryGLOn(
        ex: txn,
        date: DateTime(2026, 9, 19),
        source: 'PAYMENT',
        sourceId: 'TRACE-PAYMENT',
        lines: [
          {
            'account_id': incomingId,
            'debit': 1200.0,
            'credit': 0.0,
            'cheque_id': chequeId,
          },
          {
            'account_id': arId,
            'debit': 0.0,
            'credit': 1200.0,
            'party_type': 'CLIENT',
            'party_id': clientId,
            'repair_id': 'TRACE-REPAIR',
            'invoice_id': 'TRACE-INVOICE',
            'cheque_id': chequeId,
          },
        ],
      );
      await ChequeAccountingService.attachInitialGlOnTxn(
        txn: txn,
        chequeId: chequeId,
        glEntryId: glId,
      );
    });

    await ChequeDepositService.depositBatch(
      batchId: 'TRACE-BATCH',
      bankAccountId: bankId,
      chequeIds: [chequeId],
      depositDate: DateTime(2026, 9, 20),
      database: db,
    );
    return chequeId;
  }

  Future<int> buildIssuedTraceCheque() async {
    await db.insert('purchase_invoices', {
      'id': 'TRACE-PURCHASE',
      'supplier_id': supplierId,
      'amount_total': 900.0,
      'paid_total': 0.0,
      'date': '2026-09-19',
      'method': 'credit',
      'status': 'UNPAID',
    });
    await db.insert('vouchers', {
      'id': 'TRACE-PV',
      'voucher_type': 'PAYMENT',
      'party_type': 'SUPPLIER',
      'party_id': supplierId.toString(),
      'amount': 900.0,
      'currency': 'ILS',
      'date': '2026-09-19',
      'method': 'cheque',
      'reference': 'TRACE-PURCHASE',
      'status': 'POSTED',
      'created_at': '2026-09-19T00:00:00',
      'updated_at': '2026-09-19T00:00:00',
    });

    late int chequeId;
    await db.transaction((txn) async {
      chequeId = await ChequeAccountingService.createLinkedChequeOnTxn(
        txn: txn,
        draft: {
          'uuid': 'trace-issued-uuid',
          'instrument_key': 'trace-issued-instrument',
          'cheque_no': 'ISS-TRACE-900',
          'drawer_name': 'Yallah Workshop',
          'bank_name': 'Yallah Bank',
          'bank_branch': 'Bethlehem',
          'issue_date': '2026-09-19T00:00:00',
          'due_date': '2026-10-19T00:00:00',
          'bank_account_id': bankId,
        },
        type: ChequeType.outgoing,
        amount: 900,
        currency: 'ILS',
        sourceType: 'VOUCHER',
        sourceId: 'TRACE-PV',
        instrumentKey: 'trace-issued-instrument',
        paymentVoucherId: 'TRACE-PV',
        sourcePartyType: 'SUPPLIER',
        sourcePartyId: supplierId.toString(),
        bankAccountId: bankId,
        supplierPid: supplierId.toString(),
        recipientType: 'SUPPLIER',
        recipientId: supplierId.toString(),
        recipientName: 'Trace Supplier',
        createdBy: 'trace-owner',
      );
      await ChequeAccountingService.linkChequeToVoucherOnTxn(
        txn: txn,
        chequeId: chequeId,
        voucherType: 'PAYMENT',
        voucherId: 'TRACE-PV',
        instrumentKey: 'trace-issued-instrument',
        amount: 900,
      );
      await ChequeAccountingService.allocateChequeOnTxn(
        txn: txn,
        chequeId: chequeId,
        voucherType: 'PAYMENT',
        voucherId: 'TRACE-PV',
        allocationType: 'PURCHASE_INVOICE',
        targetId: 'TRACE-PURCHASE',
        amount: 900,
      );
    });
    return chequeId;
  }

  test('PHASE16 dashboard exposes count plus amount by direction/status',
      () async {
    final receivedId = await buildReceivedTraceCheque();
    final issuedId = await buildIssuedTraceCheque();
    final snapshot = await ChequeDashboardService.load(executor: db);
    expect(snapshot.total.count, 2);
    expect(snapshot.total.amount, 2100);
    expect(snapshot.receivedDeposited.count, 1);
    expect(snapshot.receivedDeposited.amount, 1200);
    expect(snapshot.issuedOpen.count, 1);
    expect(snapshot.issuedOpen.amount, 900);
    expect(receivedId, isNot(issuedId));
  });

  test('PHASE17 search resolves all canonical references', () async {
    final receivedId = await buildReceivedTraceCheque();
    final issuedId = await buildIssuedTraceCheque();

    for (final q in [
      'RCV-TRACE-7001',
      'Trace Customer',
      '7001',
      'TRACE-REPAIR',
      'TRACE-INVOICE',
      'TRACE-VEHICLE',
    ]) {
      final rows = await ChequeTraceService.search(q, executor: db);
      expect(rows.map((e) => e.id), contains(receivedId), reason: q);
    }
    for (final q in [
      'ISS-TRACE-900',
      'Trace Supplier',
      'TRACE-PV',
      'TRACE-PURCHASE',
      '900',
    ]) {
      final rows = await ChequeTraceService.search(q, executor: db);
      expect(rows.map((e) => e.id), contains(issuedId), reason: q);
    }
  });

  test('PHASE17/20 trace reaches voucher allocation deposit GL and actor',
      () async {
    final chequeId = await buildReceivedTraceCheque();
    final trace = await ChequeTraceService.load(chequeId, executor: db);
    expect(trace.cheque.chequeNo, 'RCV-TRACE-7001');
    expect(trace.voucherLinks.single['voucher_id'], '7001');
    expect(trace.allocations.single['target_id'], 'TRACE-REPAIR');
    expect(trace.depositItems.single['batch_id'], 'TRACE-BATCH');
    expect(trace.glEntries, isNotEmpty);
    expect(
      trace.glEntries.where((r) => r['account_code'] != null),
      isNotEmpty,
    );
    expect(
      trace.events.map((e) => e['event_type']),
      containsAll([
        'registered',
        'linked_to_voucher',
        'allocated',
        'initial_accounting',
        'status:deposited',
      ]),
    );
    final depositEvent =
        trace.events.singleWhere((e) => e['event_type'] == 'status:deposited');
    expect(depositEvent['actor_user_id'], 'trace-owner');
  });

  test('PHASE19 granular cheque permissions exist and services enforce them',
      () {
    const required = {
      PermissionKeys.chequeCreate,
      PermissionKeys.chequeEdit,
      PermissionKeys.chequeDeposit,
      PermissionKeys.chequeCollect,
      PermissionKeys.chequeReturn,
      PermissionKeys.chequeCancel,
      PermissionKeys.chequeEndorse,
      PermissionKeys.chequeDueDateEdit,
      PermissionKeys.chequeBookManage,
      PermissionKeys.chequePrint,
      PermissionKeys.chequeReportView,
      PermissionKeys.chequeReverse,
    };
    expect(PermissionKeys.all.containsAll(required), isTrue);

    final transition = File(
      'lib/features/cheques/services/cheque_accounting_service.dart',
    ).readAsStringSync();
    final deposit = File(
      'lib/features/cheques/services/cheque_deposit_service.dart',
    ).readAsStringSync();
    final books = File(
      'lib/features/cheques/services/cheque_book_service.dart',
    ).readAsStringSync();
    final receipt = File(
      'lib/features/finance/payments/services/payment_service.dart',
    ).readAsStringSync();
    final payment = File(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    ).readAsStringSync();

    expect(transition, contains('permissionForTransition(newStatus)'));
    expect(transition, contains('PermissionKeys.chequeEndorse'));
    expect(deposit, contains('PermissionKeys.chequeDeposit'));
    expect(books, contains('PermissionKeys.chequeBookManage'));
    expect(receipt, contains('PermissionKeys.chequeCreate'));
    expect(payment, contains('PermissionKeys.chequeCreate'));
  });
}
