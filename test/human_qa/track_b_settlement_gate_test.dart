import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/edit_repair_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'FIN-E2E-013 audited settlement changes gross AR revenue and outstanding',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('track_b_settlement_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    final session = await startAccountingSession(db, 'track-b-owner');
    try {
      final clientId = await db.insert('clients', {
        'name': 'Settlement Customer',
        'type': 'individual',
      });
      await db.insert('repairs', {
        'id': 'R-SETTLE',
        'client_id': clientId,
        'fileValue': 5000.0,
        'notes': '',
        'paymentType': 'cash',
        'status': 'DRAFT',
        'receivedDate': '2026-09-19T00:00:00',
        'beneficiaryName': 'Settlement Customer',
      });
      await db.insert('repair_lines', {
        'id': 'R-SETTLE-WORK',
        'repair_id': 'R-SETTLE',
        'line_type': 'work',
        'name': 'Original work',
        'qty': 1.0,
        'price': 5000.0,
        'total': 5000.0,
      });
      await db.transaction(
        (tx) => RepairAutoAccountingService.finalizeNewRepairOn(
          tx,
          'R-SETTLE',
        ),
      );
      await PaymentService.insertCanonicalReceipt(
        operationId: 'R-SETTLE-PAY-1',
        database: db,
        clientId: clientId,
        customerName: 'Settlement Customer',
        method: 'cash',
        date: DateTime(2026, 9, 19),
        allocations: const [
          ReceiptAllocationInput(
            repairId: 'R-SETTLE',
            amount: 1000.0,
            paymentId: 'R-SETTLE-P1',
          ),
        ],
      );

      final repair = Repair.fromMap(
        (await db.query(
          'repairs',
          where: 'id=?',
          whereArgs: ['R-SETTLE'],
        ))
            .single,
      );
      final result = await EditRepairService.editRepairWithAccounting(
        database: db,
        repairId: 'R-SETTLE',
        updatedRepair: repair,
        newWorks: const [
          {'name': 'Settled work', 'qty': 1.0, 'price': 4500.0},
        ],
        newParts: const [],
        notes: 'Commercial settlement',
        editedBy: 'track-b-owner',
      );
      expect(result.oldValue, 5000.0);
      expect(result.newValue, 4500.0);
      expect(result.difference, -500.0);

      final truth = await RepairFinancialTruthService.load(
        'R-SETTLE',
        executor: db,
      );
      expect(truth.repairGrossTotal, 4500.0);
      expect(truth.paymentsAllocated, 1000.0);
      expect(truth.outstandingBalance, 3500.0);
      expect(truth.customerArBalance, 3500.0);
      expect(truth.recognizedRevenue, 4500.0);
      expect(truth.isLedgerConsistent, isTrue);
      final adjustments = await db.query(
        'repair_accounting_adjustments',
        where: 'repair_id=?',
        whereArgs: ['R-SETTLE'],
      );
      expect(adjustments, hasLength(1));
      expect((adjustments.single['difference'] as num).toDouble(), -500.0);
      expect(adjustments.single['gl_entry_id'], isNotNull);

      final unbalanced = await db.rawQuery('''
        SELECT l.entry_id
        FROM gl_lines l
        GROUP BY l.entry_id
        HAVING ABS(SUM(l.debit-l.credit)) > 0.001
      ''');
      expect(unbalanced, isEmpty);
    } finally {
      await session.endEphemeralPreviewSession();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
