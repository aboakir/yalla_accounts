import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final realDb = Platform.environment['YALLAH_TRACK_B_REAL_DB'];
  final realBackup = Platform.environment['YALLAH_TRACK_B_RECON_BACKUP'];
  final realReport = Platform.environment['YALLAH_TRACK_B_CACHE_REPORT'];

  double d(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

  String repairStatus(double gross, double paid) =>
      RepairFinancialTruthService.paymentStatusFor(gross, paid);

  String purchaseStatus(String current, double total, double paid) {
    final normalized = current.toUpperCase();
    if (const {'VOID', 'CANCELLED', 'REVERSED'}.contains(normalized)) {
      return normalized;
    }
    if (paid + 0.005 >= total) return 'PAID';
    if (paid > 0.005) return 'PARTIAL';
    return 'UNPAID';
  }

  Future<List<Map<String, Object?>>> repairRows(
    DatabaseExecutor db,
  ) =>
      db.rawQuery('''
        SELECT r.id, r.fileValue, r.paidAmount, r.total_paid_amount,
               r.paymentStatus, COALESCE(p.paid,0) AS canonical_paid
        FROM repairs r
        LEFT JOIN (${RepairFinancialTruthService.paidByRepairSql}) p
          ON p.repair_id=r.id
      ''');

  Future<List<Map<String, Object?>>> purchaseRows(
    DatabaseExecutor db,
  ) =>
      db.rawQuery('''
        SELECT pi.id, pi.amount_total, pi.paid_total, pi.remaining, pi.status,
               ${PurchaseBalanceSql.paid('pi.id')} AS canonical_paid
        FROM purchase_invoices pi
      ''');
  bool repairMismatch(Map<String, Object?> row) {
    final gross = d(row['fileValue']);
    final paid = d(row['canonical_paid']);
    return (d(row['paidAmount']) - paid).abs() > 0.01 ||
        (d(row['total_paid_amount']) - paid).abs() > 0.01 ||
        '${row['paymentStatus'] ?? ''}' != repairStatus(gross, paid);
  }

  bool purchaseMismatch(Map<String, Object?> row) {
    final total = d(row['amount_total']);
    final paid = d(row['canonical_paid']);
    final remaining = math.max(total - paid, 0.0);
    final expectedStatus =
        purchaseStatus('${row['status'] ?? ''}', total, paid);
    return (d(row['paid_total']) - paid).abs() > 0.01 ||
        (d(row['remaining']) - remaining).abs() > 0.01 ||
        '${row['status'] ?? ''}'.toUpperCase() != expectedStatus;
  }

  Future<Map<String, int>> repairCaches(Database db) async {
    var repairsChanged = 0;
    var purchasesChanged = 0;
    await db.transaction((tx) async {
      for (final row in await repairRows(tx)) {
        if (!repairMismatch(row)) continue;
        final gross = d(row['fileValue']);
        final paid = d(row['canonical_paid']);
        repairsChanged += await tx.update(
          'repairs',
          {
            'paidAmount': paid,
            'total_paid_amount': paid,
            'paymentStatus': repairStatus(gross, paid),
          },
          where: 'id=?',
          whereArgs: [row['id']],
        );
      }

      for (final row in await purchaseRows(tx)) {
        if (!purchaseMismatch(row)) continue;
        final total = d(row['amount_total']);
        final paid = d(row['canonical_paid']);
        purchasesChanged += await tx.update(
          'purchase_invoices',
          {
            'paid_total': paid,
            'remaining': math.max(total - paid, 0.0),
            'status': purchaseStatus('${row['status'] ?? ''}', total, paid),
          },
          where: 'id=?',
          whereArgs: [row['id']],
        );
      }
    });
    return {
      'repair_cache_rows': repairsChanged,
      'purchase_cache_rows': purchasesChanged,
    };
  }

  test('B12 real-data compatibility caches reconcile from canonical GL',
      () async {
    final path = realDb!;
    final backup = realBackup!;
    final report = realReport!;
    expect(File(path).existsSync(), isTrue);
    expect(File(backup).existsSync(), isTrue);

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      final beforeRepairs =
          (await repairRows(db)).where(repairMismatch).toList();
      final beforePurchases =
          (await purchaseRows(db)).where(purchaseMismatch).toList();

      final changes = await repairCaches(db);
      final afterRepairs =
          (await repairRows(db)).where(repairMismatch).toList();
      final afterPurchases =
          (await purchaseRows(db)).where(purchaseMismatch).toList();
      final retry = await repairCaches(db);

      final logId = await db.insert('data_health_repair_log', {
        'run_at': DateTime.now().toUtc().toIso8601String(),
        'backup_path': backup,
        'changes_json': jsonEncode({
          'action': 'TRACK_B_FINANCIAL_CACHE_RECONCILIATION',
          ...changes,
        }),
        'before_summary': jsonEncode({
          'repair_cache_mismatch': beforeRepairs.length,
          'purchase_cache_mismatch': beforePurchases.length,
        }),
        'after_summary': jsonEncode({
          'repair_cache_mismatch': afterRepairs.length,
          'purchase_cache_mismatch': afterPurchases.length,
        }),
      });

      final payload = {
        'before_repair_cache_mismatch': beforeRepairs.length,
        'before_purchase_cache_mismatch': beforePurchases.length,
        'changes': changes,
        'after_repair_cache_mismatch': afterRepairs.length,
        'after_purchase_cache_mismatch': afterPurchases.length,
        'retry_changes': retry,
        'audit_log_id': logId,
      };
      await File(report).writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );

      expect(afterRepairs, isEmpty);
      expect(afterPurchases, isEmpty);
      expect(retry['repair_cache_rows'], 0);
      expect(retry['purchase_cache_rows'], 0);
    } finally {
      await db.close();
      DatabaseMigration.useDatabaseForTesting(null);
    }
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: realDb == null || realBackup == null || realReport == null
          ? 'Requires Track B real-data environment.'
          : false);
}
