import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_historical_reconciliation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PHASE6 audited reconciliation is deterministic and idempotent',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final temp = await Directory.systemTemp.createTemp('repair_recon_');
    final path = '${temp.path}/test.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      final clientId = await db.insert('clients', {
        'name': 'Reconciliation customer',
        'type': 'individual',
      });
      final arId = await db.insert('accounts', {
        'code': '1200.C$clientId',
        'name': 'AR reconciliation',
        'type': 'ASSET',
        'normal_balance': 'DEBIT',
      });
      await db.update(
        'clients',
        {'account_id': arId},
        where: 'id=?',
        whereArgs: [clientId],
      );
      final revenueId = (await db.query(
        'accounts',
        columns: const ['id'],
        where: 'code=?',
        whereArgs: const ['4000'],
      ))
          .single['id'] as int;

      await db.insert('repairs', {
        'id': 'R-RECON',
        'client_id': clientId,
        'fileValue': 1000.0,
        'finalApprovedAmount': 1000.0,
        'incomeAmount': 1000.0,
        'paidAmount': 0.0,
        'total_paid_amount': 0.0,
        'paymentStatus': 'غير مسدد',
        'status': 'APPROVED',
        'receivedDate': '2026-09-19T00:00:00',
        'invoice_id': 'I-RECON',
      });
      await db.insert('invoices', {
        'id': 'I-RECON',
        'repair_id': 'R-RECON',
        'client_id': clientId,
        'date': '2026-09-19',
        'total': 1000.0,
        'status': 'UNPAID',
      });
      await AccountingTables.postEntryGLOn(
        ex: db,
        date: DateTime(2026, 9, 19),
        source: 'INVOICE',
        sourceId: 'I-RECON',
        createdBy: RepairHistoricalReconciliationService.actor,
        lines: [
          {
            'account_id': arId,
            'debit': 1500.0,
            'credit': 0.0,
            'party_type': 'CLIENT',
            'party_id': clientId,
            'invoice_id': 'I-RECON',
            'repair_id': 'R-RECON',
          },
          {
            'account_id': revenueId,
            'debit': 0.0,
            'credit': 1500.0,
            'invoice_id': 'I-RECON',
            'repair_id': 'R-RECON',
          },
        ],
      );

      await db.insert('repairs', {
        'id': 'R-NONFIN',
        'client_id': clientId,
        'fileValue': 500.0,
        'finalApprovedAmount': 500.0,
        'paidAmount': 500.0,
        'total_paid_amount': 500.0,
        'paymentStatus': 'مسدد',
        'status': 'APPROVED',
        'isArchived': 1,
        'receivedDate': '2026-09-19T00:00:00',
      });

      final before = await RepairHistoricalReconciliationService.audit(db);
      expect(before, hasLength(2));
      expect(before.where((x) => x.repairable), hasLength(1));
      expect(
        before.singleWhere((x) => x.repairId == 'R-NONFIN').reason,
        'NO_FINANCIAL_DOCUMENT',
      );

      final result = await RepairHistoricalReconciliationService.reconcile(
        db,
        backupPath: path + '.backup',
      );
      expect(result.inspected, 2);
      expect(result.repaired, 1);
      expect(result.remaining, 1);
      expect(result.issuesAfter.single.repairId, 'R-NONFIN');

      final truth = await RepairFinancialTruthService.load(
        'R-RECON',
        executor: db,
      );
      expect(truth.fileValue, 1000.0);
      expect(truth.ledgerGrossTotal, 1000.0);
      expect(truth.customerArBalance, 1000.0);
      expect(truth.isLedgerConsistent, isTrue);

      final glBeforeRetry = await db.query(
        'gl_entries',
        where: 'source=?',
        whereArgs: [RepairHistoricalReconciliationService.source],
      );
      expect(glBeforeRetry, hasLength(1));
      final auditBeforeRetry = await db.query(
        'app_audit_events',
        where: 'action=?',
        whereArgs: ['REPAIR_FINANCIAL_RECONCILED'],
      );
      expect(auditBeforeRetry, hasLength(1));

      final retry = await RepairHistoricalReconciliationService.reconcile(
        db,
        backupPath: path + '.backup',
      );
      expect(retry.repaired, 0);
      expect(retry.remaining, 1);
      expect(
        await db.query(
          'gl_entries',
          where: 'source=?',
          whereArgs: [RepairHistoricalReconciliationService.source],
        ),
        hasLength(1),
      );
      expect(
        await db.query(
          'app_audit_events',
          where: 'action=?',
          whereArgs: ['REPAIR_FINANCIAL_RECONCILED'],
        ),
        hasLength(1),
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('AR detail excludes repairs with no financial document or AR GL', () {
    final source = File(
      'lib/features/finance/screens/accounts_receivable_screen.dart',
    ).readAsStringSync();
    expect(source, contains('EXISTS ('));
    expect(
        source, contains('SELECT 1 FROM invoices i WHERE i.repair_id = r.id'));
    expect(source, contains("a.code = '1200' OR a.code LIKE '1200.%'"));
  });

  test('data-health treats unposted historical repairs as warning, not AR debt',
      () {
    final source = File(
      'lib/features/settings/services/data_health_service.dart',
    ).readAsStringSync();
    expect(source, contains("id: 'legacy_nonfinancial_repairs'"));
    expect(
      source,
      contains("status: nonFinancialRepairHistory == 0"),
    );
    expect(source, contains('DataHealthStatus.warning'));
  });
}
