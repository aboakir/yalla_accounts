import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

/// P10 canonical financial truth for a repair.
///
/// Rules:
/// - commercial value: repairs.fileValue
/// - paid: net posted GL receipt movements linked to the repair
/// - repairs.total_paid_amount / repairs.paidAmount: cache only
/// - remaining never goes negative
/// - overpayment becomes customer credit
/// - customer AR is read from GL, not invoice-minus-payments shortcuts
class RepairFinancialTruth {
  const RepairFinancialTruth({
    required this.repairId,
    required this.fileValue,
    required this.paid,
    required this.remaining,
    required this.credit,
    required this.customerArBalance,
    required this.recognizedRevenue,
  });

  final String repairId;
  final double fileValue;
  final double paid;
  final double remaining;
  final double credit;
  final double customerArBalance;
  final double recognizedRevenue;

  bool get isFinanciallySettled => remaining <= 0.005;
}

class RepairFinancialTruthService {
  RepairFinancialTruthService._();

  static double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));

  static String paymentStatusFor(double fileValue, double paid) {
    if (fileValue <= 0.005) return 'مسدد';
    if (paid <= 0.005) return 'غير مسدد';
    if (paid + 0.005 >= fileValue) return 'مسدد';
    return 'مسدد جزئي';
  }

  /// Net posted receipts, credit allocations and cheque lifecycle movements.
  /// Original + reversal cancel naturally; reopening screens never posts data.
  static const String paidByRepairSql = '''
    SELECT l.repair_id, SUM(l.credit-l.debit) AS paid
    FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id
    JOIN accounts a ON a.id=l.account_id
    LEFT JOIN gl_entries original ON original.id=e.reversal_of
    WHERE (a.code='1200' OR a.code LIKE '1200.%')
      AND UPPER(COALESCE(original.source,e.source)) IN
        ('PAYMENT','PAYMENT_OUT','CREDIT_ALLOCATION','PAYMENT-ADJUST','CHEQUE_STATUS','CHEQUE_ENDORSE','VOUCHER')
    GROUP BY l.repair_id
  ''';

  static Future<double> paidForRepair(String repairId,
      {DatabaseExecutor? executor}) async {
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery(
        'SELECT paid FROM ($paidByRepairSql) WHERE repair_id=?', [repairId]);
    return rows.isEmpty ? 0.0 : _round2(_d(rows.first['paid']));
  }

  static Future<double> customerArForRepair(
    String repairId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(l.debit-l.credit),0) AS balance
      FROM gl_lines l
      LEFT JOIN accounts a ON a.id=l.account_id
      WHERE l.repair_id=?
        AND (
          a.code='1200' OR a.code LIKE '1200.%'
        )
      ''',
      [repairId],
    );
    return rows.isEmpty ? 0.0 : _round2(_d(rows.first['balance']));
  }

  static Future<double> recognizedRevenueForRepair(
    String repairId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS revenue
      FROM gl_lines l
      JOIN accounts a ON a.id=l.account_id
      WHERE l.repair_id=? AND a.code='4000'
      ''',
      [repairId],
    );
    return rows.isEmpty ? 0.0 : _round2(_d(rows.first['revenue']));
  }

  static Future<RepairFinancialTruth> load(
    String repairId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final repairs = await db.query(
      'repairs',
      columns: const ['id', 'fileValue'],
      where: 'id=?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (repairs.isEmpty) {
      throw StateError('Repair $repairId not found');
    }

    final fileValue = _round2(_d(repairs.first['fileValue']));
    final paid = await paidForRepair(repairId, executor: db);
    final remaining = _round2(math.max(fileValue - paid, 0.0));
    final credit = _round2(math.max(paid - fileValue, 0.0));
    final ar = await customerArForRepair(repairId, executor: db);
    final revenue = await recognizedRevenueForRepair(repairId, executor: db);

    return RepairFinancialTruth(
      repairId: repairId,
      fileValue: fileValue,
      paid: paid,
      remaining: remaining,
      credit: credit,
      customerArBalance: ar,
      recognizedRevenue: revenue,
    );
  }

  /// Refreshes compatibility caches only. It intentionally never changes
  /// isArchived: financial settlement is not operational close/delivery.
  static Future<void> refreshRepairPaymentCache(
    DatabaseExecutor db,
    String repairId,
  ) async {
    final rows = await db.query(
      'repairs',
      columns: const ['fileValue'],
      where: 'id=?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final fileValue = _round2(_d(rows.first['fileValue']));
    final paid = await paidForRepair(repairId, executor: db);
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              'repairs',
              {
                'paidAmount': paid,
                'total_paid_amount': paid,
                'paymentStatus': paymentStatusFor(fileValue, paid),
              },
              where: 'id=?',
              whereArgs: [repairId],
            ));
  }
}
