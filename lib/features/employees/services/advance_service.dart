// 📁 lib/features/employees/services/advance_service.dart
//
// AdvanceService — واجهة رفيعة فوق AdvanceDatabaseService
// لا منطق، فقط تحويل نداءات للحفاظ على التواقيع القائمة.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/employees/models/advance.dart';
import 'package:yalla_accounts/features/employees/services/advance_database_service.dart';

class AdvanceService {
  static const String table = 'employee_advances';

  static Future<void> createTable(Database db) async {
    await AdvanceDatabaseService.ensureTable();
  }

  // جلب الكل
  static Future<List<Advance>> getAllAdvances() async {
    return AdvanceDatabaseService.listAll();
  }

  // إدخال سجل جديد
  // يدعم method لاختيار كاش/بنك.
  static Future<Advance> insertAdvance(Advance adv, {String? method}) async {
    final id = await AdvanceDatabaseService.insertAdvance(
      advance: adv,
      method: method,
    );
    return adv.copyWith(id: id);
  }

  // حذف سجل واحد
  static Future<void> deleteAdvance(String id) async {
    await AdvanceDatabaseService.deleteAdvance(id);
  }

  // حذف كل سلف موظف
  static Future<void> deleteAdvancesByEmployee(String employeeId) async {
    await AdvanceDatabaseService.deleteByEmployee(employeeId);
  }
}
