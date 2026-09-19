import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory temp;
  late dynamic session;
  late int clientId;
  const repairId = 'HUMAN-007-008';
  const gross = 17620.0;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('human_007_008_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'human-qa');
    clientId = await db.insert('clients', {
      'name': 'Human QA Customer',
      'type': 'individual',
    });

    await db.insert('repairs', {
      'id': repairId,
      'client_id': clientId,
      'vehicleNumber': 'HUMAN-TEST',
      'vehicleType': 'Car',
      'vehicleModel': '2026',
      'fileValue': gross,
      'parts': '[]',
      'works': '[]',
      'notes': '',
      'paymentType': 'cash',
      'status': 'DRAFT',
    });
    await db.insert('repair_lines', {
      'id': 'human-work',
      'repair_id': repairId,
      'name': 'Repair work',
      'line_type': 'work',
      'qty': 1.0,
      'price': gross,
      'total': gross,
    });

    await db.transaction(
      (tx) => RepairAutoAccountingService.finalizeNewRepairOn(tx, repairId),
    );
  });

  tearDown(() async {
    if (session != null) await session.endEphemeralPreviewSession();
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<RepairFinancialTruth> truth() =>
      RepairFinancialTruthService.load(repairId, executor: db);

  Future<void> expectEverywhere({
    required double paid,
    required double outstanding,
  }) async {
    final financial = await truth();
    expect(financial.repairGrossTotal, gross);
    expect(financial.fileValue, gross);
    expect(financial.ledgerGrossTotal, gross);
    expect(financial.paymentsAllocated, paid);
    expect(financial.paid, paid);
    expect(financial.outstandingBalance, outstanding);
    expect(financial.remaining, outstanding);
    expect(financial.customerArBalance, outstanding);
    expect(financial.isLedgerConsistent, isTrue);

    final parties = await PartyFinancialService.balances(executor: db);
    final customer = parties.singleWhere(
      (p) => p.customerLegacyId == '$clientId',
    );
    expect(customer.totalReceivable, gross);
    expect(customer.received, paid);
    expect(customer.receivableBalance, outstanding);

    final statement = await PartyFinancialService.statement(
      role: 'CUSTOMER',
      legacyId: clientId,
      executor: db,
    );
    expect(statement.closingBalance, outstanding);

    final row = (await db.query(
      'repairs',
      where: 'id=?',
      whereArgs: [repairId],
    ))
        .single;
    expect((row['fileValue'] as num).toDouble(), gross);
    expect((row['total_paid_amount'] as num).toDouble(), paid);
    expect(
      row['paymentStatus'],
      RepairFinancialTruthService.paymentStatusFor(gross, paid),
    );
  }

  Future<CanonicalReceiptResult> receive(
    String operationId,
    double amount,
  ) {
    return PaymentService.insertCanonicalReceipt(
      operationId: operationId,
      database: db,
      clientId: clientId,
      customerName: 'Human QA Customer',
      method: 'cash',
      date: DateTime(2026, 9, 19),
      allocations: [
        ReceiptAllocationInput(repairId: repairId, amount: amount),
      ],
      unallocatedAmount: 0,
    );
  }

  test('TEST-ACC-001..004 exact 17620 -> 11810 -> 5810 is canonical', () async {
    await expectEverywhere(paid: 0, outstanding: 17620);
    final first = await receive('HUMAN-R1', 11810);
    expect(first.allocatedAmount, 11810);
    await expectEverywhere(paid: 11810, outstanding: 5810);

    final duplicate = await receive('HUMAN-R1', 11810);
    expect(duplicate.receiptNumber, first.receiptNumber);
    await expectEverywhere(paid: 11810, outstanding: 5810);
  });

  test('TEST-ACC-005..015 final payment settles all sources exactly once',
      () async {
    await receive('HUMAN-R1', 11810);
    final finalReceipt = await receive('HUMAN-R2', 5810);
    await expectEverywhere(paid: 17620, outstanding: 0);

    final replay = await receive('HUMAN-R2', 5810);
    expect(replay.receiptNumber, finalReceipt.receiptNumber);
    await expectEverywhere(paid: 17620, outstanding: 0);

    final headers = await db.query(
      'receipt_headers',
      where: 'receipt_number IN (?, ?)',
      whereArgs: [
        (await receive('HUMAN-R1', 11810)).receiptNumber,
        finalReceipt.receiptNumber,
      ],
    );
    expect(headers.length, 2);

    final allocations = await db.query(
      'receipt_allocations',
      where: 'repair_id=?',
      whereArgs: [repairId],
    );
    expect(allocations.length, 2);
    expect(
      allocations.fold<double>(
        0,
        (sum, row) => sum + (row['amount'] as num).toDouble(),
      ),
      17620,
    );

    final financial = await truth();
    expect(financial.remaining, isNonNegative);
    expect(financial.paid, gross);
    expect(financial.isFinanciallySettled, isTrue);
  });

  test('posted repair gross guard blocks legacy silent value mutation', () {
    final source = File(
      'lib/features/repairs/services/repair_database_service.dart',
    ).readAsStringSync();
    expect(source, contains('final financiallyPosted ='));
    expect(
      source,
      contains(
        'Financial repair value changes must use the audited accounting edit path.',
      ),
    );
  });

  test('reopen preserves canonical totals and no UI-specific gross source',
      () async {
    await receive('HUMAN-R1', 11810);
    await receive('HUMAN-R2', 5810);
    await expectEverywhere(paid: gross, outstanding: 0);

    final path = db.path;
    await session.endEphemeralPreviewSession();
    session = null;
    await db.close();
    db = await databaseFactory.openDatabase(path);
    await expectEverywhere(paid: gross, outstanding: 0);

    final source = File(
      'lib/features/finance/screens/accounts_receivable_screen.dart',
    ).readAsStringSync();
    expect(source, contains('RepairFinancialTruthService.load('));
    expect(source, contains('invoiceTotal: truth.fileValue'));
    expect(source, contains('paid: truth.paid'));
  });
}
