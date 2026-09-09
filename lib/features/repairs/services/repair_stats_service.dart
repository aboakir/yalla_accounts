import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
// 📁 lib/features/repairs/services/repair_stats_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class RepairStatsService {
  // مصدر قاعدة البيانات الموحّد
  static Future<Database> get _db async => DBService.database;

  // عدد ملفات الإصلاح الكلي
  static Future<int> getTotalRepairsCount() async {
    final db = await _db;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM repairs');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // عدد الملفات حسب حالة المركبة (vehicleStatus)
  static Future<int> getRepairsCountByStatus(String status) async {
    final db = await _db;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM repairs WHERE vehicleStatus = ?',
      [status],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ✅ مجموع قيمة الملفات:
  //    نأخذ أولاً finalApprovedAmount إن وجِد،
  //    ثم fileValue كاحتياطي.
  static Future<double> getTotalFileValue() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(fileValue),0) AS v
      FROM repairs
    ''');

    final v = rows.first['v'];
    return (v as num?)?.toDouble() ?? 0.0;
  }

  // ✅ مجموع المدفوع من كافة الملفات:
  //    نستخدم total_paid_amount الجديد،
  static Future<double> getTotalPaidAmount() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(paid),0) AS v FROM (${RepairFinancialTruthService.paidByRepairSql}) WHERE repair_id IS NOT NULL
    ''');

    final v = rows.first['v'];
    return (v as num?)?.toDouble() ?? 0.0;
  }

  // ملخص شهري لعدد الملفات وقيمتها ومدفوعها
  static Future<List<Map<String, dynamic>>> getMonthlyRepairSummary() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      WITH paid AS (${RepairFinancialTruthService.paidByRepairSql})
      SELECT
        strftime('%Y-%m', r.receivedDate) AS month,
        COUNT(*) AS repair_count,
        COALESCE(SUM(r.fileValue),0) AS total_file_value,
        COALESCE(SUM(COALESCE(p.paid,0)),0) AS total_paid_amount
      FROM repairs r
      LEFT JOIN paid p ON p.repair_id=r.id
      GROUP BY month
      ORDER BY month DESC
    ''');

    return rows;
  }

  // عدد الملفات حسب حالة السداد (paymentStatus)
  static Future<Map<String, int>> getRepairsCountByPaymentStatus() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT paymentStatus AS s, COUNT(*) AS c
      FROM repairs
      GROUP BY paymentStatus
    ''');

    final Map<String, int> out = {
      'مسدد': 0,
      'مسدد جزئي': 0,
      'غير مسدد': 0,
    };

    for (final m in rows) {
      final s = m['s'] as String?;
      final c = (m['c'] as num?)?.toInt() ?? 0;
      if (s != null && out.containsKey(s)) {
        out[s] = c;
      }
    }
    return out;
  }
}
