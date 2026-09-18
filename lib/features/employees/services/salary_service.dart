// 📁 lib/features/employees/services/salary_service.dart
//
// SalaryService — legacy salary table compatibility (mutations disabled)
// ✅ تصحيح الأكواد: 5100، 2140.E[emp]، 1120.E[emp]، 1000/1010
// ✅ party_type='EMPLOYEE' + party_id=employee_id (TEXT)
// ✅ يمنع التكرار عبر uq_gl_source(source,source_id) في GL (موجود لديك)
// ✅ لا إنشاء ملفات جديدة ولا تعديل معمارية، فقط هذا الملف
//
// القيود المحاسبية (بعد التصحيح):
// 1) اعتماد الراتب (approval)
//    Dr 5100 مصروف رواتب = gross
//    Cr 1120.E[emp] سلف موظف = advances_applied (إن > 0)
//    Cr 2140.E[emp] مستحقات رواتب = net
//
// 2) صرف الراتب (payment)
//    Dr 2140.E[emp] = المبلغ المصروف
//    Cr 1000 الصندوق أو 1010 البنك حسب method
//
// ملاحظات:
// - نعتمد على DBService فقط: getAccountIdByCode / ensureAccount / postEntryGL / reverseEntryGL
// - naming للحسابات الفرعية: "2140.E[employeeId]" و "1120.E[employeeId]"

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class SalaryService {
  static const String table = 'salaries';

  static Future<Database> get _db async => DBService.database;

  /// إنشاء الجدول إن لم يكن موجودًا + أعمدة ربط GL
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table(
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        month TEXT,
        date TEXT NOT NULL,                 -- ISO
        gross REAL NOT NULL,                -- إجمالي الراتب
        advances_applied REAL NOT NULL DEFAULT 0,  -- سلف مستهلكة ضمن هذا الراتب
        deductions REAL NOT NULL DEFAULT 0,        -- خصومات أخرى
        net REAL NOT NULL,                  -- الصافي = gross - advances_applied - deductions
        status TEXT NOT NULL DEFAULT 'approved',   -- approved | paid | void
        note TEXT,
        gl_entry_id_approval INTEGER,
        gl_entry_id_payment INTEGER,
        payment_date TEXT
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_emp_date ON $table(employee_id, date);',
    );
  }

  // Legacy table kept read-only for backward compatibility.

  // ================= Commands =================

  /// اعتماد راتب: ينشئ سجل + قيد GL بالتصميم المصحّح
  /// القيد:
  ///   Dr 5100 مصروف رواتب (gross)
  ///   Cr 1120.E[emp] (advances_applied) إن > 0
  ///   Cr 2140.E[emp] (net)
  @Deprecated('Use PayrollEntitlementService.accrueFromAttendance')
  static Future<Map<String, Object?>> approveSalary({
    String? id,
    required String employeeId,
    required DateTime date,
    String? month,
    required double gross,
    double advancesApplied = 0,
    double deductions = 0,
    String? note,
  }) async {
    throw StateError(
      'Direct salary approval is disabled. Use attendance-driven payroll entitlement.',
    );
  }

  /// دفع راتب: قيد سداد ويحدّث السجل إلى paid
  /// Dr 2140.E[emp] / Cr 1000|1010
  @Deprecated('Use PayrollDatabaseService.pay -> payment voucher')
  static Future<void> paySalary({
    required String id, // salary id المعتمد سابقًا
    DateTime? paymentDate,
    double? amount, // افتراضي = net من السجل
    String? method, // 'cash' افتراضيًا أو بنك/تحويل/بطاقة/شيك
    String? note,
  }) async {
    throw StateError(
      'Direct salary payment is disabled. Create a payment voucher linked to the payroll entitlement.',
    );
  }

  /// Legacy salary approval mutation is disabled in Stage 4.
  @Deprecated('Use PayrollEntitlementService and formal reversal')
  static Future<void> voidSalaryApproval(String id) async {
    throw StateError(
      'Legacy salary approval mutation is disabled. Use payroll entitlement and formal accounting reversal.',
    );
  }

  // ================= Queries =================

  static Future<List<Map<String, Object?>>> listByEmployee(
    String employeeId,
  ) async {
    final db = await _db;
    await createTable(db);
    return db.query(
      table,
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      orderBy: 'date DESC',
    );
  }
}
