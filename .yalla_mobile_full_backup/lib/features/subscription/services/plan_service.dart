import 'package:yalla_accounts/core/services/db_service.dart';
import '../models/plan.dart';

class PlanService {
  // جلب جميع الباقات الفعالة
  Future<List<Plan>> getAllActivePlans() async {
    final db = await DBService.database;

    final results = await db.query(
      'plans',
      where: 'isActive = ?',
      whereArgs: [1],
    );

    return results.map((row) => Plan.fromMap(row)).toList();
  }

  // جلب باقة محددة حسب ID
  Future<Plan?> getPlanById(String id) async {
    final db = await DBService.database;

    final results = await db.query(
      'plans',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isNotEmpty) {
      return Plan.fromMap(results.first);
    }
    return null;
  }
}
