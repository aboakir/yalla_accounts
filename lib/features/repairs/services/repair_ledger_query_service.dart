import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

/// P10 repair financial reporting.
/// Revenue is read from GL account 4000. Paid/outstanding amounts are derived
/// from payments and repairs.fileValue; legacy paidAmount is never a source of
/// truth here.
class RepairLedgerQueryService {
  static Future<Database> get _db async => DBService.database;

  static const _paidCte = '''
    WITH paid AS (
      SELECT
        COALESCE(NULLIF(repair_id,''), relatedRepairId) AS repair_id,
        SUM(amount) AS paid
      FROM payments
      WHERE COALESCE(isIncome,1)=1
      GROUP BY COALESCE(NULLIF(repair_id,''), relatedRepairId)
    )
  ''';

  static Future<List<Map<String, dynamic>>> getMonthlyRevenue() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT
        strftime('%Y-%m', e.date) AS month,
        COALESCE(SUM(l.credit-l.debit),0) AS totalRevenue
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code='4000'
      GROUP BY month
      ORDER BY month ASC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getMonthlyOutstandingDebts() async {
    final db = await _db;
    return db.rawQuery('''
      $_paidCte
      SELECT
        strftime('%Y-%m', r.receivedDate) AS month,
        COALESCE(SUM(MAX(r.fileValue-COALESCE(p.paid,0),0)),0) AS totalDebt
      FROM repairs r
      LEFT JOIN paid p ON p.repair_id=r.id
      WHERE r.fileValue-COALESCE(p.paid,0) > 0.005
      GROUP BY month
      ORDER BY month ASC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getRepairCountsByMonth() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT
        strftime('%Y-%m', receivedDate) AS month,
        COUNT(*) AS repairCount
      FROM repairs
      GROUP BY month
      ORDER BY month ASC
    ''');
  }

  static Future<List<Map<String, dynamic>>>
      getRevenueByBeneficiaryType() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT
        COALESCE(r.beneficiaryType,'غير معروف') AS beneficiaryType,
        COALESCE(SUM(l.credit-l.debit),0) AS totalRevenue
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      LEFT JOIN repairs r ON r.id=l.repair_id
      WHERE a.code='4000'
      GROUP BY COALESCE(r.beneficiaryType,'غير معروف')
      ORDER BY totalRevenue DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getTopOutstandingRepairs({
    int limit = 5,
  }) async {
    final db = await _db;
    return db.rawQuery('''
      $_paidCte
      SELECT
        r.id,
        r.vehicleModel,
        r.beneficiaryName,
        r.fileValue,
        COALESCE(p.paid,0) AS paidAmount,
        MAX(r.fileValue-COALESCE(p.paid,0),0) AS debt
      FROM repairs r
      LEFT JOIN paid p ON p.repair_id=r.id
      WHERE r.fileValue-COALESCE(p.paid,0) > 0.005
      ORDER BY debt DESC
      LIMIT ?
    ''', [limit]);
  }

  static Future<List<Map<String, dynamic>>> getYearlyRevenue() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT
        strftime('%Y', e.date) AS year,
        COALESCE(SUM(l.credit-l.debit),0) AS totalRevenue
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code='4000'
      GROUP BY year
      ORDER BY year ASC
    ''');
  }

  static Future<int> getOverdueUnpaidRepairsCount() async {
    final db = await _db;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    final result = await db.rawQuery('''
      $_paidCte
      SELECT COUNT(*) AS count
      FROM repairs r
      LEFT JOIN paid p ON p.repair_id=r.id
      WHERE r.fileValue-COALESCE(p.paid,0) > 0.005
        AND r.receivedDate <= ?
    ''', [cutoff]);

    return Sqflite.firstIntValue(result) ?? 0;
  }
}
