import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class RepairLedgerQueryService {
  static Future<Database> get _db async => DBService.database;

  /// 🔹 إجمالي الإيرادات شهريًا
  static Future<List<Map<String, dynamic>>> getMonthlyRevenue() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT 
        strftime('%Y-%m', receivedDate) AS month,
        SUM(fileValue) AS totalRevenue
      FROM repairs
      GROUP BY month
      ORDER BY month ASC
    ''');
  }

  /// 🔹 إجمالي الذمم غير المسددة شهريًا
  static Future<List<Map<String, dynamic>>> getMonthlyOutstandingDebts() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT 
        strftime('%Y-%m', receivedDate) AS month,
        SUM(fileValue - paidAmount) AS totalDebt
      FROM repairs
      WHERE paymentStatus != 'مسدد'
      GROUP BY month
      ORDER BY month ASC
    ''');
  }

  /// 🔹 عدد عمليات الإصلاح لكل شهر
  static Future<List<Map<String, dynamic>>> getRepairCountsByMonth() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT 
        strftime('%Y-%m', receivedDate) AS month,
        COUNT(*) AS repairCount
      FROM repairs
      GROUP BY month
      ORDER BY month ASC
    ''');
  }

  /// 🔹 توزيع الإيرادات حسب نوع الجهة (أفراد/تأمين)
  static Future<List<Map<String, dynamic>>>
      getRevenueByBeneficiaryType() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT 
        beneficiaryType,
        SUM(fileValue) AS totalRevenue
      FROM repairs
      GROUP BY beneficiaryType
    ''');
  }

  /// 🔹 أعلى الملفات التي فيها ذمم غير مسددة
  static Future<List<Map<String, dynamic>>> getTopOutstandingRepairs(
      {int limit = 5}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT 
        id,
        vehicleModel,
        beneficiaryName,
        fileValue,
        paidAmount,
        (fileValue - paidAmount) AS debt
      FROM repairs
      WHERE paymentStatus != 'مسدد'
      ORDER BY debt DESC
      LIMIT ?
    ''', [limit]);
  }

  /// 🔹 إجمالي الإيرادات سنويًا
  static Future<List<Map<String, dynamic>>> getYearlyRevenue() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT 
        strftime('%Y', receivedDate) AS year,
        SUM(fileValue) AS totalRevenue
      FROM repairs
      GROUP BY year
      ORDER BY year ASC
    ''');
  }

  /// 🔔 عدد الملفات غير المسددة منذ أكثر من 30 يومًا
  static Future<int> getOverdueUnpaidRepairsCount() async {
    final db = await _db;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM repairs
      WHERE paymentStatus != 'مسدد'
      AND receivedDate <= ?
    ''', [cutoff]);

    return Sqflite.firstIntValue(result) ?? 0;
  }
}
