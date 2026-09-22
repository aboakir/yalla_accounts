import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/account_statements/customers/services/customer_account_statement_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/reports/providers/ar_aging_provider.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int clientId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('customer_ar_stage2_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'ar-stage2-owner');

    await PartyFinancialService.createParty(
      name: 'Stage2 Customer',
      phone: '0599000000',
      address: 'Bethlehem',
      customer: true,
      supplier: false,
      database: db,
    );
    clientId = (await db.query(
      'clients',
      columns: const ['id'],
      where: 'name=?',
      whereArgs: const ['Stage2 Customer'],
      limit: 1,
    ))
        .single['id'] as int;
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  Future<void> seedRepair(String id, double value) async {
    await db.insert('repairs', {
      'id': id,
      'client_id': clientId,
      'fileValue': value,
      'notes': '',
      'paymentType': 'cash',
      'status': 'DRAFT',
      'receivedDate': '2026-09-20T00:00:00',
      'beneficiaryName': 'Stage2 Customer',
      'beneficiaryType': 'أفراد',
      'vehicleNumber': 'V-$id',
      'vehicleType': 'Sedan',
      'vehicleModel': '2026',
    });
    await db.insert('repair_lines', {
      'id': '$id-WORK',
      'repair_id': id,
      'line_type': 'work',
      'name': 'Repair work',
      'qty': 1.0,
      'price': value,
      'total': value,
    });
    await db.transaction(
      (tx) => RepairAutoAccountingService.finalizeNewRepairOn(tx, id),
    );
  }

  Future<double> arBalance() async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit-l.credit),0) AS balance
      FROM gl_lines l
      JOIN accounts a ON a.id=l.account_id
      WHERE (a.code='1200' OR a.code LIKE '1200.%')
        AND UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
        AND CAST(l.party_id AS INTEGER)=?
    ''', [clientId]);
    return (rows.single['balance'] as num).toDouble();
  }

  Future<void> expectBalanced() async {
    final unbalanced = await db.rawQuery('''
      SELECT l.entry_id
      FROM gl_lines l
      GROUP BY l.entry_id
      HAVING ABS(SUM(l.debit-l.credit)) > 0.001
    ''');
    expect(unbalanced, isEmpty);
    final total = await db.rawQuery(
      'SELECT COALESCE(SUM(debit-credit),0) AS d FROM gl_lines',
    );
    expect((total.single['d'] as num).toDouble(), closeTo(0, 0.001));
  }

  Map<String, dynamic> chequeDraft(String key, double amount) => {
        'uuid': 'uuid-$key',
        'instrument_key': key,
        'cheque_no': 'NO-$key',
        'drawer_name': 'Stage2 Customer',
        'bank_name': 'Palestine Bank',
        'bank_branch': 'Bethlehem',
        'issue_date': '2026-09-20T00:00:00',
        'due_date': '2026-10-20T00:00:00',
        'amount': amount,
      };

  test('AR2-010 full customer lifecycle reconciles statement aging and GL',
      () async {
    const repairs = <String, double>{
      'AR2-R1': 1000,
      'AR2-R2': 2000,
      'AR2-R3': 1500,
      'AR2-R4': 1200,
      'AR2-R5': 800,
    };
    for (final entry in repairs.entries) {
      await seedRepair(entry.key, entry.value);
    }

    final cash1 = await PaymentService.insertCanonicalReceipt(
      operationId: 'AR2-CASH-1',
      database: db,
      clientId: clientId,
      customerName: 'Stage2 Customer',
      method: 'cash',
      date: DateTime(2026, 9, 20),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'AR2-R1',
          amount: 600,
          paymentId: 'AR2-CASH-1-R1',
        ),
      ],
    );
    final bank1 = await PaymentService.insertCanonicalReceipt(
      operationId: 'AR2-BANK-1',
      database: db,
      clientId: clientId,
      customerName: 'Stage2 Customer',
      method: 'bank',
      date: DateTime(2026, 9, 20),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'AR2-R1',
          amount: 400,
          paymentId: 'AR2-BANK-1-R1',
        ),
      ],
    );
    final multi = await PaymentService.insertCanonicalReceipt(
      operationId: 'AR2-MULTI-1',
      database: db,
      clientId: clientId,
      customerName: 'Stage2 Customer',
      method: 'cash',
      date: DateTime(2026, 9, 20),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'AR2-R2',
          amount: 500,
          paymentId: 'AR2-MULTI-R2',
        ),
        ReceiptAllocationInput(
          repairId: 'AR2-R3',
          amount: 300,
          paymentId: 'AR2-MULTI-R3',
        ),
      ],
    );
    final cheque1 = await PaymentService.insertCanonicalReceipt(
      operationId: 'AR2-CHEQUE-1',
      database: db,
      clientId: clientId,
      customerName: 'Stage2 Customer',
      method: 'cheque',
      date: DateTime(2026, 9, 20),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'AR2-R4',
          amount: 200,
          paymentId: 'AR2-CHEQUE-R4',
        ),
      ],
      chequeDraft: chequeDraft('AR2-CHEQUE-1', 200),
    );

    final overpay = await PaymentService.insertCanonicalReceipt(
      operationId: 'AR2-OVERPAY-1',
      database: db,
      clientId: clientId,
      customerName: 'Stage2 Customer',
      method: 'cash',
      date: DateTime(2026, 9, 20),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'AR2-R5',
          amount: 1000,
          paymentId: 'AR2-OVERPAY-R5',
        ),
      ],
      unallocatedPaymentId: 'AR2-OVERPAY-CREDIT',
    );
    expect(cash1.allocatedAmount, 600);
    expect(bank1.allocatedAmount, 400);
    expect(multi.allocatedAmount, 800);
    expect(cheque1.allocatedAmount, 200);
    expect(overpay.allocatedAmount, 800);
    expect(overpay.customerCredit, 200);
    expect(
      await PaymentService.customerCreditForClient(clientId, executor: db),
      200,
    );

    final retry = await PaymentService.insertCanonicalReceipt(
      operationId: 'AR2-OVERPAY-1',
      database: db,
      clientId: clientId,
      customerName: 'Stage2 Customer',
      method: 'cash',
      date: DateTime(2026, 9, 20),
      allocations: const [
        ReceiptAllocationInput(
          repairId: 'AR2-R5',
          amount: 1000,
          paymentId: 'AR2-OVERPAY-R5',
        ),
      ],
      unallocatedPaymentId: 'AR2-OVERPAY-CREDIT',
    );
    expect(retry.receiptNumber, overpay.receiptNumber);
    expect(
      await db.query(
        'receipt_requests',
        where: 'operation_id=?',
        whereArgs: const ['AR2-OVERPAY-1'],
      ),
      hasLength(1),
    );
    await expectLater(
      PaymentService.insertCanonicalReceipt(
        operationId: 'AR2-OVERPAY-1',
        database: db,
        clientId: clientId,
        customerName: 'Stage2 Customer',
        method: 'cash',
        date: DateTime(2026, 9, 20),
        allocations: const [
          ReceiptAllocationInput(
            repairId: 'AR2-R5',
            amount: 999,
            paymentId: 'AR2-OVERPAY-R5',
          ),
        ],
        unallocatedPaymentId: 'AR2-OVERPAY-CREDIT',
      ),
      throwsStateError,
    );

    final applied = await PaymentService.allocateCustomerCreditToRepair(
      clientId: clientId,
      repairId: 'AR2-R2',
      amount: 150,
      notes: 'Stage2 credit allocation',
    );
    expect(applied, 150);
    expect(
      await PaymentService.customerCreditForClient(clientId, executor: db),
      50,
    );
    final r2Truth = await RepairFinancialTruthService.load(
      'AR2-R2',
      executor: db,
    );
    expect(r2Truth.paid, 650);
    expect(r2Truth.remaining, 1350);

    expect(
      await db.query(
        'receipt_allocations',
        where: 'receipt_number=? AND allocation_type=?',
        whereArgs: [multi.receiptNumber, 'REPAIR'],
      ),
      hasLength(2),
    );
    expect(
      await db.query(
        'payments',
        where: 'repair_id=? AND amount>0',
        whereArgs: const ['AR2-R1'],
      ),
      hasLength(2),
    );

    await PaymentService.reverseReceipt(
      bank1.receiptNumber,
      reason: 'Stage2 bank reversal',
      database: db,
    );
    await PaymentService.reverseReceipt(
      cheque1.receiptNumber,
      reason: 'Stage2 cheque reversal',
      database: db,
    );
    await PaymentService.reverseReceipt(
      cash1.receiptNumber,
      reason: 'Stage2 cash reversal',
      database: db,
    );
    await expectLater(
      PaymentService.reverseReceipt(
        cash1.receiptNumber,
        reason: 'duplicate reversal',
        database: db,
      ),
      throwsStateError,
    );

    final chequeRows = await db.query(
      'cheques',
      where: 'source_type=? AND source_id=?',
      whereArgs: ['RECEIPT', cheque1.receiptNumber.toString()],
    );
    expect(chequeRows, hasLength(1));
    expect(
      (chequeRows.single['status'] ?? '').toString().toLowerCase(),
      contains('cancel'),
    );

    final statement = await CustomerAccountStatementService.load(
      clientId: clientId,
      to: DateTime(2026, 9, 30),
      executor: db,
    );
    final glAr = await arBalance();
    expect(glAr, closeTo(4700, 0.001));
    expect(statement.closingBalance, closeTo(glAr, 0.001));
    expect(statement.lines, isNotEmpty);
    expect(
      statement.lines.every(
        (line) => line.source.isNotEmpty && line.entryId > 0,
      ),
      isTrue,
    );
    final aging = await ARAgingProvider.fetch(
      asOf: DateTime(2026, 9, 30),
      executor: db,
    );
    final agingNet = aging.fold<double>(0, (sum, row) => sum + row.balance);
    expect(agingNet, closeTo(glAr, 0.001));

    final customerRows = await db.query(
      'clients',
      where: 'name=?',
      whereArgs: const ['Stage2 Customer'],
    );
    expect(customerRows, hasLength(1));
    final partyRoles = await db.query(
      'party_roles',
      where: 'role=? AND legacy_id=?',
      whereArgs: ['CUSTOMER', clientId.toString()],
    );
    expect(partyRoles, hasLength(1));
    expect(
      await db.query('repairs', where: 'client_id=?', whereArgs: [clientId]),
      hasLength(5),
    );

    final summary = await PartyFinancialService.balances(executor: db);
    final customerSummary =
        summary.singleWhere((row) => row.customerLegacyId == '$clientId');
    expect(customerSummary.receivableBalance, closeTo(glAr, 0.001));
    await expectBalanced();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
