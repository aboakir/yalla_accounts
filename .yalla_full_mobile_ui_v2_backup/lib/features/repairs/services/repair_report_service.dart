import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:sqflite/sqflite.dart';

class RepairReportService {
  static Future<Database> get _db async => DBService.database;

  /// 🔹 تقرير الذمم المدينة حسب الجهة المستفيدة
  static Future<Map<String, double>>
      getOutstandingReceivablesGroupedByBeneficiary() async {
    final db = await _db;

    final results = await db.rawQuery('''
      SELECT beneficiaryName, SUM(fileValue - paidAmount) AS outstanding
      FROM repairs
      WHERE (fileValue - paidAmount) > 0
      GROUP BY beneficiaryName
    ''');

    final Map<String, double> receivables = {};
    for (final row in results) {
      final name = (row['beneficiaryName'] ?? 'غير معروف').toString();
      final value = (row['outstanding'] as num?)?.toDouble() ?? 0.0;
      receivables[name] = value;
    }
    return receivables;
  }

  /// 🔹 تقرير عدد وقيمة الإصلاحات شهريًا
  static Future<Map<String, Map<String, double>>>
      getMonthlyRepairsReport() async {
    final db = await _db;

    final results = await db.rawQuery('''
      SELECT 
        strftime('%Y-%m', receivedDate) AS month,
        COUNT(*)                        AS totalCount,
        IFNULL(SUM(fileValue),0)        AS totalValue
      FROM repairs
      GROUP BY month
      ORDER BY month ASC
    ''');

    final Map<String, Map<String, double>> report = {};
    for (final row in results) {
      final month = (row['month'] ?? '').toString();
      final count = (row['totalCount'] as num?)?.toDouble() ?? 0.0;
      final value = (row['totalValue'] as num?)?.toDouble() ?? 0.0;
      report[month] = {'count': count, 'value': value};
    }
    return report;
  }

  /// 🔹 تقرير إجمالي الإصلاحات سنويًا
  static Future<Map<String, double>> getYearlyRepairsValue() async {
    final db = await _db;

    final results = await db.rawQuery('''
      SELECT 
        strftime('%Y', receivedDate) AS year,
        IFNULL(SUM(fileValue),0)     AS totalValue
      FROM repairs
      GROUP BY year
      ORDER BY year ASC
    ''');

    final Map<String, double> report = {};
    for (final row in results) {
      final year = (row['year'] ?? '').toString();
      final value = (row['totalValue'] as num?)?.toDouble() ?? 0.0;
      report[year] = value;
    }
    return report;
  }
}
