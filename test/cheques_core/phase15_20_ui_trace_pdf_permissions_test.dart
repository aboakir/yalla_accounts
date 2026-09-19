import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_dashboard_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_pdf_report_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_trace_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late AuthSessionService ownerSession;
  late int bankId;
  late int clientId;
  late int supplierId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cheques_15_20_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    ownerSession = await startAccountingSession(db, 'cheque-ui-owner');
    bankId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1010'],
      limit: 1,
    ))
        .single['id'] as int;
    clientId = await db.insert('clients', {
      'name': 'Trace Customer',
      'type': 'individual',
    });
    supplierId = await db.insert('suppliers', {'name': 'Trace Supplier'});
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    await ownerSession.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<int> insertCheque({
    required String number,
    required ChequeDirection direction,
    required ChequeStatus status,
    required double amount,
    DateTime? dueDate,
    int? client,
    int? supplier,
  }) async {
    final now = DateTime(2026, 9, 19);
    return db.insert('cheques', {
      'uuid': 'uuid-$number',
      'instrument_key': 'instrument-$number',
      'cheque_no': number,
      'cheque_type':
          direction == ChequeDirection.received ? 'incoming' : 'outgoing',
      'direction':
          direction == ChequeDirection.received ? 'RECEIVED' : 'ISSUED',
      'status': status.name,
      'drawer_name': direction == ChequeDirection.received
          ? 'Trace Customer'
          : 'Yallah Workshop',
      'recipient_name':
          direction == ChequeDirection.issued ? 'Trace Supplier' : 'Workshop',
      'bank_name': direction == ChequeDirection.received
          ? 'Drawer Bank'
          : 'Workshop Bank',
      'bank_branch': 'Bethlehem',
      'amount': amount,
      'currency': 'ILS',
      'issue_date': now.toIso8601String(),
      'due_date': (dueDate ?? DateTime(2026, 9, 22)).toIso8601String(),
      'client_id': client,
      'supplier_pid': supplier?.toString(),
      'source_party_type':
          client != null ? 'CLIENT' : (supplier != null ? 'SUPPLIER' : null),
      'source_party_id': client?.toString() ?? supplier?.toString(),
      'bank_account_id': direction == ChequeDirection.issued ? bankId : null,
      'is_legacy_incomplete': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  test('PHASE15/16 dashboard derives COUNT + AMOUNT from canonical lifecycle',
      () async {
    await insertCheque(
      number: 'R-HELD',
      direction: ChequeDirection.received,
      status: ChequeStatus.received,
      amount: 1000,
      client: clientId,
    );
    await insertCheque(
      number: 'R-DEP',
      direction: ChequeDirection.received,
      status: ChequeStatus.deposited,
      amount: 2000,
      client: clientId,
    );
    await insertCheque(
      number: 'R-COL',
      direction: ChequeDirection.received,
      status: ChequeStatus.collected,
      amount: 3000,
      client: clientId,
    );
    await insertCheque(
      number: 'I-OPEN',
      direction: ChequeDirection.issued,
      status: ChequeStatus.issued,
      amount: 4000,
      supplier: supplierId,
    );
    await insertCheque(
      number: 'I-CLEAR',
      direction: ChequeDirection.issued,
      status: ChequeStatus.cleared,
      amount: 5000,
      supplier: supplierId,
    );

    final data = await ChequeDashboardService.load(
      executor: db,
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
    );
    expect(data.total.count, 5);
    expect(data.total.amount, 15000);
    expect(data.receivedHeld.count, 1);
    expect(data.receivedHeld.amount, 1000);
    expect(data.receivedDeposited.amount, 2000);
    expect(data.receivedCollected.amount, 3000);
    expect(data.issuedOpen.amount, 4000);
    expect(data.issuedCleared.amount, 5000);

    final supplierOnly = await ChequeDashboardService.load(
      executor: db,
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
      party: 'Trace Supplier',
    );
    expect(supplierOnly.total.count, 2);
    expect(supplierOnly.total.amount, 9000);
  });

  test('PHASE17 search and trace reach voucher party allocation and GL',
      () async {
    await db.insert('receipt_headers', {
      'receipt_number': 77,
      'client_id': clientId,
      'date': '2026-09-19',
      'method': 'cheque',
      'total_amount': 700,
      'allocated_amount': 700,
      'credit_amount': 0,
      'status': 'posted',
      'created_at': DateTime.now().toIso8601String(),
    });
    final chequeId = await insertCheque(
      number: 'TRACE-700',
      direction: ChequeDirection.received,
      status: ChequeStatus.received,
      amount: 700,
      client: clientId,
    );
    await db.update(
      'cheques',
      {
        'receipt_voucher_id': 77,
        'source_type': 'RECEIPT',
        'source_id': '77',
      },
      where: 'id=?',
      whereArgs: [chequeId],
    );
    await db.insert('cheque_voucher_links', {
      'cheque_id': chequeId,
      'voucher_type': 'RECEIPT',
      'voucher_id': '77',
      'instrument_key': 'instrument-TRACE-700',
      'amount': 700,
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('cheque_allocations', {
      'cheque_id': chequeId,
      'voucher_type': 'RECEIPT',
      'voucher_id': '77',
      'allocation_type': 'REPAIR',
      'target_id': 'REPAIR-XYZ',
      'amount': 700,
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('cheque_events', {
      'cheque_id': chequeId,
      'event_type': 'registered',
      'from_status': null,
      'to_status': 'received',
      'event_date': DateTime.now().toIso8601String(),
      'actor_user_id': 'cheque-ui-owner',
      'created_at': DateTime.now().toIso8601String(),
    });
    final incomingId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1020'],
      limit: 1,
    ))
        .single['id'] as int;
    final arId = await db.insert('accounts', {
      'code': '1200.C$clientId',
      'name': 'Trace AR',
      'type': 'ASSET',
      'normal_balance': 'DEBIT',
    });
    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 9, 19),
      source: 'PAYMENT',
      sourceId: 'TRACE-PAY',
      lines: [
        {
          'account_id': incomingId,
          'debit': 700.0,
          'credit': 0.0,
          'cheque_id': chequeId
        },
        {
          'account_id': arId,
          'debit': 0.0,
          'credit': 700.0,
          'party_type': 'CLIENT',
          'party_id': clientId,
          'repair_id': 'REPAIR-XYZ',
          'cheque_id': chequeId
        },
      ],
    );

    expect(
        (await ChequeTraceService.search('TRACE-700', executor: db)).single.id,
        chequeId);
    expect(
        (await ChequeTraceService.search('Trace Customer', executor: db))
            .map((e) => e.id),
        contains(chequeId));
    expect(
        (await ChequeTraceService.search('REPAIR-XYZ', executor: db))
            .map((e) => e.id),
        contains(chequeId));
    expect(
        (await ChequeTraceService.search('77', executor: db)).map((e) => e.id),
        contains(chequeId));

    final trace = await ChequeTraceService.load(chequeId, executor: db);
    expect(trace.voucherLinks, hasLength(1));
    expect(trace.allocations.single['target_id'], 'REPAIR-XYZ');
    expect(trace.parties.single['name'], 'Trace Customer');
    expect(trace.glEntries, hasLength(2));
    expect(trace.events, hasLength(1));
  });
  test(
      'PHASE18 report PDF renders real cheque rows and voucher PDF contracts include cheque metadata',
      () async {
    await insertCheque(
      number: 'PDF-RCV',
      direction: ChequeDirection.received,
      status: ChequeStatus.deposited,
      amount: 1250,
      client: clientId,
    );
    await insertCheque(
      number: 'PDF-ISS',
      direction: ChequeDirection.issued,
      status: ChequeStatus.issued,
      amount: 850,
      supplier: supplierId,
    );

    final incoming = await ChequePdfReportService.loadRows(
      ChequePdfReportKind.incoming,
      executor: db,
    );
    final outgoing = await ChequePdfReportService.loadRows(
      ChequePdfReportKind.outgoing,
      executor: db,
    );
    final deposited = await ChequePdfReportService.loadRows(
      ChequePdfReportKind.deposited,
      executor: db,
    );
    expect(incoming.map((e) => e.chequeNo), contains('PDF-RCV'));
    expect(outgoing.map((e) => e.chequeNo), contains('PDF-ISS'));
    expect(deposited.map((e) => e.chequeNo), contains('PDF-RCV'));

    final bytes = await ChequePdfReportService.generate(
      ChequePdfReportKind.incoming,
      executor: db,
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');

    final receiptPdf = File(
      'lib/features/vouchers/pdf/receipt_voucher_pdf.dart',
    ).readAsStringSync();
    final paymentPdf = File(
      'lib/features/vouchers/pdf/payment_voucher_pdf.dart',
    ).readAsStringSync();
    for (final source in [receiptPdf, paymentPdf]) {
      expect(source, contains('chequeNumber'));
      expect(source, contains('chequeBank'));
      expect(source, contains('chequeCurrency'));
      expect(source, contains('chequeDueDate'));
      expect(source, contains('الحالة:'));
      expect(source, isNot(contains('�')));
    }
  });

  test('PHASE19 UI and service contracts use granular cheque permissions',
      () async {
    final policy = File(
      'lib/core/security/authorization_policy.dart',
    ).readAsStringSync();
    for (final key in const [
      'CHEQUE_CREATE',
      'CHEQUE_EDIT',
      'CHEQUE_DEPOSIT',
      'CHEQUE_COLLECT',
      'CHEQUE_RETURN',
      'CHEQUE_CANCEL',
      'CHEQUE_ENDORSE',
      'CHEQUE_DUE_DATE_EDIT',
      'CHEQUE_BOOK_MANAGE',
      'CHEQUE_PRINT',
      'CHEQUE_REPORT_VIEW',
      'CHEQUE_REVERSE',
    ]) {
      expect(policy, contains(key));
    }
    final details = File(
      'lib/features/cheques/screens/cheque_details_screen.dart',
    ).readAsStringSync();
    final collection = File(
      'lib/features/cheques/screens/cheques_collection_screen.dart',
    ).readAsStringSync();
    expect(details, contains('_can(PermissionKeys.chequeCancel)'));
    expect(details, contains('_can(PermissionKeys.chequeEndorse)'));
    expect(collection, contains('_canDeposit'));
    expect(collection, contains('_canCollect'));
    expect(collection, contains('_canReturn'));

    final chequeId = await insertCheque(
      number: 'PERM-1',
      direction: ChequeDirection.received,
      status: ChequeStatus.received,
      amount: 100,
      client: clientId,
    );
    await ownerSession.endEphemeralPreviewSession();
    final viewer = AppUser(
      id: 'viewer-user',
      name: 'Viewer',
      email: '',
      role: 'viewer',
      status: 'active',
      createdAt: DateTime.now(),
    );
    await db.insert('users', {
      'id': viewer.id,
      'name': viewer.name,
      'password': 'test-only',
      'role': 'viewer',
      'is_owner': 0,
      'status': 'active',
      'created_at': viewer.createdAt.toIso8601String(),
    });
    final viewerSession = AuthSessionService(databaseProvider: () async => db);
    await viewerSession.createSession(viewer);
    AuthorizationGuard.enableInteractiveEnforcement();

    await expectLater(
      ChequeService().updateDueDate(
        chequeId: chequeId,
        dueDate: DateTime(2026, 10, 20),
      ),
      throwsStateError,
    );
    AuthorizationGuard.disableInteractiveEnforcement();
    await viewerSession.endEphemeralPreviewSession();
  });
  test('PHASE20 due-date change appends immutable timeline and audit event',
      () async {
    final chequeId = await insertCheque(
      number: 'AUDIT-1',
      direction: ChequeDirection.received,
      status: ChequeStatus.received,
      amount: 500,
      client: clientId,
    );
    final before = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
    ))
        .single['due_date'];

    await ChequeService().updateDueDate(
      chequeId: chequeId,
      dueDate: DateTime(2026, 11, 1),
      reason: 'Customer requested new maturity',
    );

    final trace = await ChequeTraceService.load(chequeId, executor: db);
    final dueEvents = trace.events
        .where((e) => e['event_type'] == 'due_date_changed')
        .toList();
    expect(dueEvents, hasLength(1));
    expect(dueEvents.single['reason'], 'Customer requested new maturity');
    expect(dueEvents.single['actor_user_id'], isNotNull);
    expect(dueEvents.single['note'].toString(), contains(before.toString()));

    final audit = await db.query(
      'app_audit_events',
      where: 'action=? AND entity_id=?',
      whereArgs: ['CHEQUE_DUE_DATE_CHANGED', chequeId.toString()],
    );
    expect(audit, hasLength(1));

    await expectLater(
      db.delete(
        'cheque_events',
        where: 'cheque_id=? AND event_type=?',
        whereArgs: [chequeId, 'due_date_changed'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
      'PHASE15 sidebar removes direct cheque creation and exposes cheque books',
      () {
    final sidebar = File(
      'lib/core/widgets/sidebar/yalla_sidebar.dart',
    ).readAsStringSync();
    final add = File(
      'lib/features/cheques/screens/cheque_add_screen.dart',
    ).readAsStringSync();
    expect(sidebar, isNot(contains("(Icons.add, 'إضافة شيك'")));
    expect(sidebar, contains('دفاتر الشيكات'));
    expect(sidebar, contains('إيداع للتحصيل / قيد التحصيل'));
    expect(add, contains('إنشاء الشيك يبدأ من السند المالي'));
    expect(add, contains('AppRoutes.receiptVoucher'));
    expect(add, contains('AppRoutes.paymentVoucher'));
  });
}
