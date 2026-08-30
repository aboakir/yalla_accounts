// 📁 lib/features/employees/services/salary_service.dart
//
// SalaryService — اعتماد وصرف الرواتب مع قيود GL (DB v29 → v29b)
// ✅ تصحيح الأكواد: 5100، 2140.E<emp>، 1120.E<emp>، 1000/1010
// ✅ party_type='EMPLOYEE' + party_id=employee_id (TEXT)
// ✅ يمنع التكرار عبر uq_gl_source(source,source_id) في GL (موجود لديك)
// ✅ لا إنشاء ملفات جديدة ولا تعديل معمارية، فقط هذا الملف
//
// القيود المحاسبية (بعد التصحيح):
// 1) اعتماد الراتب (approval)
//    Dr 5100 مصروف رواتب = gross
//    Cr 1120.E<emp> سلف موظف = advances_applied (إن > 0)
//    Cr 2140.E<emp> مستحقات رواتب = net
//
// 2) صرف الراتب (payment)
//    Dr 2140.E<emp> = المبلغ المصروف
//    Cr 1000 الصندوق أو 1010 البنك حسب method
//
// ملاحظات:
// - نعتمد على DBService فقط: getAccountIdByCode / ensureAccount / postEntryGL / reverseEntryGL
// - naming للحسابات الفرعية: "2140.E<employeeId>" و "1120.E<employeeId>"

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
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

  // ================= Helpers =================

  static double _round(num v) => double.parse(v.toStringAsFixed(2));

  /// تأكد من وجود حساب رئيسي/فرعي حسب الكود
  static Future<int> _requireAccount({
    required String code,
    required String name,
    required String type, // ASSET/LIABILITY/EQUITY/REVENUE/EXPENSE
    required String normalBalance, // DEBIT/CREDIT
  }) async {
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: name,
      type: type,
      normalBalance: normalBalance,
    );
  }

  /// صياغة كود حساب فرعي لموظف: 2140.E<id> أو 1120.E<id>
  static String _empSubCode(String root, String employeeId) =>
      '$root.E$employeeId';

  /// احصل على حساب مستحقات الموظف 2140.E<id>
  static Future<int> _accPayrollPayableId(String employeeId) async {
    final code = _empSubCode('2140', employeeId);
    return _requireAccount(
      code: code,
      name: 'رواتب مستحقة - $employeeId',
      type: 'LIABILITY',
      normalBalance: 'CREDIT',
    );
    // ملاحظة: حساب 2140 الجذر يجب أن يكون موجودًا مسبقًا لديك.
  }

  /// احصل على حساب سلف الموظف 1120.E<id>
  static Future<int> _accEmployeeAdvanceId(String employeeId) async {
    final code = _empSubCode('1120', employeeId);
    return _requireAccount(
      code: code,
      name: 'سلف موظف - $employeeId',
      type: 'ASSET',
      normalBalance: 'DEBIT',
    );
  }

  /// حساب مصروف الرواتب 5100
  static Future<int> _accSalaryExpenseId() async {
    return _requireAccount(
      code: '5100',
      name: 'مصروف رواتب',
      type: 'EXPENSE',
      normalBalance: 'DEBIT',
    );
  }

  static bool _isBankMethod(String? m) {
    final s = (m ?? '').toLowerCase();
    return s.contains('bank') ||
        s.contains('تحويل') ||
        s.contains('transfer') ||
        s.contains('visa') ||
        s.contains('master') ||
        s.contains('بطاقة') ||
        s.contains('شيك') ||
        s.contains('cheque') ||
        s.contains('check');
  }

  static Future<int> _cashOrBankId(String? method) async {
    final bank = _isBankMethod(method);
    final code = bank ? '1010' : '1000';
    return (await DBService.getAccountIdByCode(code)) ??
        await DBService.ensureAccount(
          code: code,
          name: bank ? 'البنك' : 'الصندوق',
          type: 'ASSET',
          normalBalance: 'DEBIT',
        );
  }

  // ================= Commands =================

  /// اعتماد راتب: ينشئ سجل + قيد GL بالتصميم المصحّح
  /// القيد:
  ///   Dr 5100 مصروف رواتب (gross)
  ///   Cr 1120.E<emp> (advances_applied) إن > 0
  ///   Cr 2140.E<emp> (net)
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
    final db = await _db;
    await createTable(db);

    final id0 = id ?? const Uuid().v4();
    final net = _round(gross - advancesApplied - deductions);
    if (net < 0) {
      throw StateError('Net salary cannot be negative');
    }

    return db.transaction<Map<String, Object?>>((txn) async {
      // حسابات مطلوبة
      final accExpense = await _accSalaryExpenseId();
      final accAdvEmp = await _accEmployeeAdvanceId(employeeId);
      final accPayroll = await _accPayrollPayableId(employeeId);

      // سطور GL
      final lines = <Map<String, Object?>>[
        {
          'account_id': accExpense,
          'debit': _round(gross),
          'credit': 0.0,
          'party_type': 'EMPLOYEE',
          'party_id': employeeId,
          'invoice_id': null,
          'repair_id': null,
        },
        if (advancesApplied > 0)
          {
            'account_id': accAdvEmp,
            'debit': 0.0,
            'credit': _round(advancesApplied),
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
            'invoice_id': null,
            'repair_id': null,
          },
        {
          'account_id': accPayroll,
          'debit': 0.0,
          'credit': _round(net),
          'party_type': 'EMPLOYEE',
          'party_id': employeeId,
          'invoice_id': null,
          'repair_id': null,
        },
      ];

      // GL
      final glId = await DBService.postEntryGL(
        date: date,
        source: 'PAYROLL', // توحيد الاسم
        sourceId: id0, // يمنع التكرار عبر uq_gl_source
        note: note,
        lines: lines,
      );

      // سجل الرواتب
      final row = <String, Object?>{
        'id': id0,
        'employee_id': employeeId,
        'month': month,
        'date': date.toIso8601String(),
        'gross': _round(gross),
        'advances_applied': _round(advancesApplied),
        'deductions': _round(deductions),
        'net': _round(net),
        'status': 'approved',
        'note': note,
        'gl_entry_id_approval': glId,
      };

      await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.fail);
      return row;
    });
  }

  /// دفع راتب: قيد سداد ويحدّث السجل إلى paid
  /// Dr 2140.E<emp> / Cr 1000|1010
  static Future<void> paySalary({
    required String id, // salary id المعتمد سابقًا
    DateTime? paymentDate,
    double? amount, // افتراضي = net من السجل
    String? method, // 'cash' افتراضيًا أو بنك/تحويل/بطاقة/شيك
    String? note,
  }) async {
    final db = await _db;
    await createTable(db);

    await db.transaction((txn) async {
      final rows = await txn.query(
        table,
        columns: ['employee_id', 'net', 'status', 'gl_entry_id_payment'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Salary $id not found');

      final r = rows.first;
      if (r['gl_entry_id_payment'] != null) {
        throw StateError('Salary $id already paid');
      }
      final status = (r['status'] as String?) ?? 'approved';
      if (status != 'approved') {
        throw StateError('Salary $id status must be approved to pay');
      }

      final employeeId = r['employee_id'] as String;
      final pay = _round((amount ?? (r['net'] as num).toDouble()));
      final when = paymentDate ?? DateTime.now();

      final accPayroll = await _accPayrollPayableId(employeeId);
      final accCashOrBank = await _cashOrBankId(method);

      final glId = await DBService.postEntryGL(
        date: when,
        source: 'PAYROLL_PAY',
        sourceId: id,
        note: note,
        lines: [
          {
            'account_id': accPayroll,
            'debit': pay,
            'credit': 0.0,
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
            'invoice_id': null,
            'repair_id': null,
          },
          {
            'account_id': accCashOrBank,
            'debit': 0.0,
            'credit': pay,
            'party_type': null,
            'party_id': null,
            'invoice_id': null,
            'repair_id': null,
          },
        ],
      );

      await txn.update(
        table,
        {
          'status': 'paid',
          'payment_date': when.toIso8601String(),
          'gl_entry_id_payment': glId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// عكس اعتماد الراتب: يعكس GL ويجعل السجل void
  static Future<void> voidSalaryApproval(String id) async {
    final db = await _db;
    await createTable(db);

    await db.transaction((txn) async {
      final rows = await txn.query(
        table,
        columns: ['status', 'gl_entry_id_approval', 'gl_entry_id_payment'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Salary $id not found');
      if (rows.first['gl_entry_id_payment'] != null) {
        throw StateError('Cannot void: already paid');
      }

      final glId = rows.first['gl_entry_id_approval'] as int?;
      if (glId != null) {
        await DBService.reverseEntryGL(
          glId,
          note: 'Reverse salary approval $id',
        );
      }

      await txn.update(
        table,
        {'status': 'void', 'gl_entry_id_approval': null},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
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
