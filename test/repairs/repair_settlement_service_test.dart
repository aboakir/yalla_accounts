import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_settlement_service.dart';

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
    temp = await Directory.systemTemp.createTemp('repair_settlement_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'settlement-owner');
    clientId = await db.insert('clients', {
      'name': 'Settlement Customer',
      'type': 'individual',
    });
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> seedRepair(String id, {double value = 7000}) async {
    await db.insert('repairs', {
      'id': id,
      'client_id': clientId,
      'fileValue': value,
      'notes': '',
      'paymentType': 'cash',
      'status': 'DRAFT',
      'receivedDate': '2026-09-20T00:00:00',
      'beneficiaryName': 'Settlement Customer',
      'beneficiaryType': 'أفراد',
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

  Future<void> pay(
    String id,
    double amount, {
    String? operationId,
  }) =>
      PaymentService.insertCanonicalReceipt(
        operationId: operationId ?? '$id-PAY-${amount.toStringAsFixed(0)}',
        database: db,
        clientId: clientId,
        customerName: 'Settlement Customer',
        method: 'cash',
        date: DateTime(2026, 9, 20),
        allocations: [
          ReceiptAllocationInput(
            repairId: id,
            amount: amount,
            paymentId:
                '${operationId ?? '$id-P-${amount.toStringAsFixed(0)}'}-ALLOC',
          ),
        ],
      );

  Future<void> expectBalanced() async {
    final rows = await db.rawQuery('''
      SELECT l.entry_id
      FROM gl_lines l
      GROUP BY l.entry_id
      HAVING ABS(SUM(l.debit-l.credit)) > 0.001
    ''');
    expect(rows, isEmpty);
  }

  test('minus settlement updates gross value AR revenue and history atomically',
      () async {
    await seedRepair('R-MINUS');
    await db.update(
      'repairs',
      {'status': 'CLOSED'},
      where: 'id=?',
      whereArgs: ['R-MINUS'],
    );

    final result = await RepairSettlementService.apply(
      repairId: 'R-MINUS',
      adjustment: -500,
      reason: 'خصم / سداد مبكر',
      note: 'Final commercial discount',
      actorId: 'owner-1',
      database: db,
    );

    expect(result.oldValue, 7000);
    expect(result.adjustment, -500);
    expect(result.newValue, 6500);
    expect(result.remaining, 6500);
    expect(result.customerArBalance, 6500);
    expect(result.recognizedRevenue, 6500);
    expect(result.credit, 0);

    final truth =
        await RepairFinancialTruthService.load('R-MINUS', executor: db);
    expect(truth.fileValue, 6500);
    expect(truth.customerArBalance, 6500);
    expect(truth.recognizedRevenue, 6500);
    expect(truth.isLedgerConsistent, isTrue);

    final repair =
        (await db.query('repairs', where: 'id=?', whereArgs: ['R-MINUS']))
            .single;
    expect(repair['status'], 'CLOSED',
        reason: 'settlement must not reopen a closed operational file');

    final settlement = (await db.query(
      'repair_settlements',
      where: 'repair_id=?',
      whereArgs: ['R-MINUS'],
    ))
        .single;
    expect((settlement['adjustment'] as num).toDouble(), -500);
    expect(settlement['reason'], 'خصم / سداد مبكر');
    expect(settlement['created_by'], 'owner-1');
    expect(settlement['gl_entry_id'], isNotNull);

    final entry = (await db.query(
      'gl_entries',
      where: 'source=? AND source_id=?',
      whereArgs: ['REPAIR_SETTLEMENT', result.id],
    ))
        .single;
    expect(entry['id'], result.glEntryId);
    final adjustment = (await db.query(
      'repair_accounting_adjustments',
      where: 'id=?',
      whereArgs: [result.id],
    ))
        .single;
    expect((adjustment['difference'] as num).toDouble(), -500);
    await expectBalanced();
  });

  test('plus settlement increases file AR and revenue', () async {
    await seedRepair('R-PLUS');

    final result = await RepairSettlementService.apply(
      repairId: 'R-PLUS',
      adjustment: 500,
      reason: 'إضافة أعمال أو قطع',
      database: db,
    );

    expect(result.newValue, 7500);
    expect(result.remaining, 7500);
    expect(result.customerArBalance, 7500);
    expect(result.recognizedRevenue, 7500);
    final truth =
        await RepairFinancialTruthService.load('R-PLUS', executor: db);
    expect(truth.ledgerGrossTotal, 7500);
    expect(truth.isLedgerConsistent, isTrue);
    await expectBalanced();
  });

  test('settlement can close outstanding exactly after a payment', () async {
    await seedRepair('R-CLOSE');
    await pay('R-CLOSE', 4800);

    final before =
        await RepairFinancialTruthService.load('R-CLOSE', executor: db);
    expect(before.paid, 4800);
    expect(before.remaining, 2200);

    final result = await RepairSettlementService.apply(
      repairId: 'R-CLOSE',
      adjustment: -2200,
      reason: 'اتفاق نهائي مع العميل',
      database: db,
    );

    expect(result.newValue, 4800);
    expect(result.paid, 4800);
    expect(result.remaining, 0);
    expect(result.credit, 0);
    expect(result.customerArBalance, 0);
    final repair =
        (await db.query('repairs', where: 'id=?', whereArgs: ['R-CLOSE']))
            .single;
    expect(repair['paymentStatus'], 'مسدد');
    final legacyTable = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='accounts_receivable'",
    );
    if (legacyTable.isNotEmpty) {
      final legacy = await db.query(
        'accounts_receivable',
        where: 'repairId=?',
        whereArgs: ['R-CLOSE'],
      );
      expect(legacy, isEmpty);
    }
    await expectBalanced();
  });

  test(
      'minus settlement below paid becomes customer credit, never negative due',
      () async {
    await seedRepair('R-CREDIT');
    await pay('R-CREDIT', 4800);

    final result = await RepairSettlementService.apply(
      repairId: 'R-CREDIT',
      adjustment: -2700,
      reason: 'اتفاق نهائي مع العميل',
      database: db,
    );

    expect(result.newValue, 4300);
    expect(result.paid, 4800);
    expect(result.remaining, 0);
    expect(result.credit, 500);
    expect(result.customerArBalance, -500);
    final truth =
        await RepairFinancialTruthService.load('R-CREDIT', executor: db);
    expect(truth.remaining, 0);
    expect(truth.credit, 500);
    expect(truth.ledgerGrossTotal, 4300);
    expect(truth.isLedgerConsistent, isTrue);
    await expectBalanced();
  });

  test('settlement heals legacy duplicate invoice posting without auto marker',
      () async {
    // Reproduce the live legacy state: the repair/invoice says 2,400,
    // while historical GL still carries a duplicated 4,800 gross posting.
    await seedRepair('R-LEGACY-DUP', value: 4800);
    await db.update(
      'repairs',
      {
        'fileValue': 2400.0,
        'incomeAmount': 2400.0,
        'finalApprovedAmount': 2400.0,
        'notes': '',
      },
      where: 'id=?',
      whereArgs: ['R-LEGACY-DUP'],
    );
    await pay('R-LEGACY-DUP', 2300);

    final broken = await RepairFinancialTruthService.load(
      'R-LEGACY-DUP',
      executor: db,
    );
    expect(broken.fileValue, 2400);
    expect(broken.paid, 2300);
    expect(broken.ledgerGrossTotal, 4800);
    expect(broken.customerArBalance, 2500);
    expect(broken.recognizedRevenue, 4800);
    expect(broken.isLedgerConsistent, isFalse);

    final result = await RepairSettlementService.apply(
      repairId: 'R-LEGACY-DUP',
      adjustment: -100,
      reason: 'خصم / سداد مبكر',
      database: db,
    );

    expect(result.newValue, 2300);
    expect(result.paid, 2300);
    expect(result.remaining, 0);
    expect(result.customerArBalance, 0);
    expect(result.recognizedRevenue, 2300);
    expect(result.adjustment, -100);
    final healed = await RepairFinancialTruthService.load(
      'R-LEGACY-DUP',
      executor: db,
    );
    expect(healed.ledgerGrossTotal, 2300);
    expect(healed.isLedgerConsistent, isTrue);
    await expectBalanced();
  });

  test('settlement that would make file value negative is rejected atomically',
      () async {
    await seedRepair('R-INVALID');
    final before =
        await RepairFinancialTruthService.load('R-INVALID', executor: db);

    await expectLater(
      RepairSettlementService.apply(
        repairId: 'R-INVALID',
        adjustment: -7001,
        reason: 'تصحيح قيمة الملف',
        database: db,
      ),
      throwsStateError,
    );

    final after =
        await RepairFinancialTruthService.load('R-INVALID', executor: db);
    expect(after.fileValue, before.fileValue);
    expect(after.customerArBalance, before.customerArBalance);
    final history = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='repair_settlements'",
    );
    if (history.isNotEmpty) {
      expect(
        await db.query(
          'repair_settlements',
          where: 'repair_id=?',
          whereArgs: ['R-INVALID'],
        ),
        isEmpty,
      );
    }
    expect(
      await db.query(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['REPAIR_SETTLEMENT'],
      ),
      isEmpty,
    );
    await expectBalanced();
  });

  test('10000 then 3000 receipt then -4000 settlement then final receipt',
      () async {
    await seedRepair('R-10K', value: 10000);
    await pay('R-10K', 3000, operationId: 'R-10K-PAY-1');

    final settled = await RepairSettlementService.apply(
      repairId: 'R-10K',
      adjustment: -4000,
      reason: 'اتفاق نهائي مع العميل',
      operationId: 'R-10K-SETTLE-1',
      database: db,
    );

    expect(settled.newValue, 6000);
    expect(settled.paid, 3000);
    expect(settled.remaining, 3000);
    expect(settled.customerArBalance, 3000);
    expect(settled.recognizedRevenue, 6000);

    await pay('R-10K', 3000, operationId: 'R-10K-PAY-2');
    final finalTruth =
        await RepairFinancialTruthService.load('R-10K', executor: db);
    expect(finalTruth.fileValue, 6000);
    expect(finalTruth.paid, 6000);
    expect(finalTruth.remaining, 0);
    expect(finalTruth.credit, 0);
    expect(finalTruth.customerArBalance, 0);
    expect(finalTruth.recognizedRevenue, 6000);
    expect(finalTruth.isLedgerConsistent, isTrue);
    await expectBalanced();
  });

  test('failure after repair update before GL posting rolls back everything',
      () async {
    await seedRepair('R-ROLLBACK', value: 7000);
    final repairBefore = (await db.query(
      'repairs',
      where: 'id=?',
      whereArgs: ['R-ROLLBACK'],
    ))
        .single;
    final glCountBefore =
        (await db.rawQuery('SELECT COUNT(*) c FROM gl_entries')).single['c'];

    await db.execute('''
      CREATE TRIGGER qa_fail_repair_settlement_gl
      BEFORE INSERT ON gl_entries
      WHEN NEW.source='REPAIR_SETTLEMENT'
      BEGIN
        SELECT RAISE(ABORT, 'TEST_FORCED_GL_FAILURE');
      END
    ''');

    await expectLater(
      RepairSettlementService.apply(
        repairId: 'R-ROLLBACK',
        adjustment: -500,
        reason: 'اختبار rollback',
        operationId: 'R-ROLLBACK-SETTLE-1',
        database: db,
      ),
      throwsA(isA<DatabaseException>()),
    );

    final repairAfter = (await db.query(
      'repairs',
      where: 'id=?',
      whereArgs: ['R-ROLLBACK'],
    ))
        .single;
    expect(repairAfter['fileValue'], repairBefore['fileValue']);
    expect(repairAfter['incomeAmount'], repairBefore['incomeAmount']);
    expect(repairAfter['finalApprovedAmount'],
        repairBefore['finalApprovedAmount']);
    expect(
      (await db.rawQuery('SELECT COUNT(*) c FROM gl_entries')).single['c'],
      glCountBefore,
    );
    expect(
      await RepairSettlementService.historyForRepair(
        'R-ROLLBACK',
        executor: db,
      ),
      isEmpty,
    );
  });

  test(
      'same settlement operation id is idempotent and changed retry is rejected',
      () async {
    await seedRepair('R-IDEMPOTENT', value: 7000);
    const operationId = 'R-IDEMPOTENT-SETTLE-1';

    final first = await RepairSettlementService.apply(
      repairId: 'R-IDEMPOTENT',
      adjustment: -500,
      reason: 'خصم / سداد مبكر',
      operationId: operationId,
      database: db,
    );
    final second = await RepairSettlementService.apply(
      repairId: 'R-IDEMPOTENT',
      adjustment: -500,
      reason: 'خصم / سداد مبكر',
      operationId: operationId,
      database: db,
    );

    expect(second.id, first.id);
    expect(second.newValue, first.newValue);
    expect(
      await db.query(
        'repair_settlements',
        where: 'operation_id=?',
        whereArgs: [operationId],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['REPAIR_SETTLEMENT', operationId],
      ),
      hasLength(1),
    );

    await expectLater(
      RepairSettlementService.apply(
        repairId: 'R-IDEMPOTENT',
        adjustment: -600,
        reason: 'خصم / سداد مبكر',
        operationId: operationId,
        database: db,
      ),
      throwsStateError,
    );
    final truth =
        await RepairFinancialTruthService.load('R-IDEMPOTENT', executor: db);
    expect(truth.fileValue, 6500);
    expect(truth.recognizedRevenue, 6500);
    expect(truth.isLedgerConsistent, isTrue);
    await expectBalanced();
  });
}
