import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
// ✅ Fixed v31: add columns first, then indexes
// 📁 lib/features/employees/services/employee_database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';

class EmployeeDatabaseService {
  static const String tableName = 'employees';
  static Future<Database> get _db async => DBService.database;

  // ───────────── Schema + Migration v31 ─────────────

  /// ينشئ الجدول ثم يرقّيه للأنواع الأربعة ثم يبني الفهارس.
  static Future<void> ensureTable() async {
    final db = await _db;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        full_name TEXT NOT NULL DEFAULT '',
        employee_code TEXT NOT NULL,
        job_title TEXT NOT NULL DEFAULT '',
        hire_date TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',

        -- الرواتب (قديمًا شهري فقط)
        base_salary REAL NOT NULL DEFAULT 0,
        allowances REAL NOT NULL DEFAULT 0,
        deductions REAL NOT NULL DEFAULT 0,
        advances REAL NOT NULL DEFAULT 0,

        -- الحضور
        total_work_days INTEGER NOT NULL DEFAULT 0,
        total_hours REAL NOT NULL DEFAULT 0,
        absences INTEGER NOT NULL DEFAULT 0,
        late_days INTEGER NOT NULL DEFAULT 0,

        -- ملاحظات وملفات
        notes TEXT NOT NULL DEFAULT '',
        photo_url TEXT,
        contract_url TEXT,

        -- تواريخ
        last_salary_paid_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,

        -- الدفع والروتين
        payment_method TEXT NOT NULL DEFAULT 'cash',
        work_days_per_week INTEGER NOT NULL DEFAULT 6,
        hours_per_day INTEGER NOT NULL DEFAULT 8
      )
    ''');

    // 1) أضف أعمدة v31 إن لم تكن موجودة
    await _ensureV31Columns(db);

    // 2) فهارس أساسية (بدون contract_type)
    await _ensureBaseIndexes(db);

    // 3) فهرس النوع بعد التأكد من وجود العمود
    await _ensureContractTypeIndex(db);
  }

  // ───────────── Migration helpers ─────────────

  static Future<void> _ensureV31Columns(Database db) async {
    Future<void> add(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {
        // العمود موجود مسبقًا
      }
    }

    await add(
        'ALTER TABLE $tableName ADD COLUMN contract_type TEXT NOT NULL DEFAULT \'monthly\'');
    await add('ALTER TABLE $tableName ADD COLUMN weekly_rate REAL');
    await add('ALTER TABLE $tableName ADD COLUMN daily_rate REAL');
    await add('ALTER TABLE $tableName ADD COLUMN contract_amount REAL');
    await add('ALTER TABLE $tableName ADD COLUMN contract_desc TEXT');
    await add('ALTER TABLE $tableName ADD COLUMN contract_due_date TEXT');
    await add(
        'ALTER TABLE $tableName ADD COLUMN contract_status TEXT'); // newTask|inProgress|ready|approved|paid
    await add('ALTER TABLE $tableName ADD COLUMN cycle_anchor TEXT');
  }

  static Future<void> _ensureBaseIndexes(Database db) async {
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_${tableName}_code ON $tableName(employee_code)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_name ON $tableName(full_name COLLATE NOCASE)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_status ON $tableName(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_created ON $tableName(created_at)');
  }

  static Future<void> _ensureContractTypeIndex(Database db) async {
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_${tableName}_contract_type ON $tableName(contract_type)');
    } catch (_) {
      // لو كانت قاعدة قديمة جدًا بدون العمود لأي سبب، تجاهل.
    }
  }

  // ───────────── CRUD ─────────────

  static void _validate(Employee employee) {
    if (employee.fullName.trim().isEmpty ||
        employee.employeeCode.trim().isEmpty) {
      throw ArgumentError('اسم الموظف ورقمه مطلوبان.');
    }
    for (final amount in [
      employee.baseSalaryForType,
      employee.allowances,
      employee.deductions
    ]) {
      if (!amount.isFinite || amount < 0) {
        throw ArgumentError(
            'الأجر والبدلات والخصومات يجب أن تكون أرقاماً موجبة أو صفراً.');
      }
    }
  }

  static Future<void> insert(Employee employee) async {
    _validate(employee);
    await ensureTable();
    final db = await _db;
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              tableName,
              employee.toMap(),
              conflictAlgorithm: ConflictAlgorithm.fail,
            ));
  }

  static Future<void> upsert(Employee employee) async {
    _validate(employee);
    await ensureTable();
    final db = await _db;
    await SyncFoundationService.transaction(db, (txn) async {
      final exists = await txn.query(tableName,
          columns: ['id'], where: 'id=?', whereArgs: [employee.id]);
      if (exists.isEmpty) {
        await txn.insert(tableName, employee.toMap(),
            conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await txn.update(tableName, employee.toMap(),
            where: 'id=?', whereArgs: [employee.id]);
      }
    });
  }

  static Future<void> upsertBulk(List<Employee> employees) async {
    for (final employee in employees) {
      await upsert(employee);
    }
  }

  static Future<void> update(Employee employee) async {
    _validate(employee);
    await ensureTable();
    final db = await _db;
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              tableName,
              employee.toMap(),
              where: 'id = ?',
              whereArgs: [employee.id],
            ));
  }

  static Future<int> patch(String id, Map<String, Object?> fields) async {
    await ensureTable();
    final db = await _db;
    fields.removeWhere((k, v) => v == null);
    if (fields.isEmpty) return 0;
    fields['updated_at'] = DateTime.now().toIso8601String();
    return SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn
            .update(tableName, fields, where: 'id = ?', whereArgs: [id]));
  }

  static Future<void> delete(String id) async {
    await ensureTable();
    final db = await _db;
    await SyncFoundationService.transaction(db, (txn) async {
      final activity = await txn.rawQuery(
          "SELECT id FROM attendance WHERE employeeId=? UNION ALL SELECT id FROM payroll_runs WHERE employee_id=? UNION ALL SELECT id FROM vouchers WHERE party_type='EMPLOYEE' AND party_id=? LIMIT 1",
          [id, id, id]);
      if (activity.isNotEmpty) {
        throw StateError(
            'للموظف حضور أو حركات مالية؛ غيّر حالته إلى غير نشط بدلاً من حذفه.');
      }
      await txn.delete(tableName, where: 'id=?', whereArgs: [id]);
    });
  }

  // ───────────── Queries ─────────────

  static Future<List<Employee>> getAll({String? orderBy}) async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query(
      tableName,
      orderBy: orderBy ?? 'full_name COLLATE NOCASE ASC',
    );
    return rows.map(Employee.fromMap).toList();
  }

  static Future<List<Employee>> getAllEmployees() => getAll();

  static Future<Employee?> getById(String id) async {
    await ensureTable();
    final db = await _db;
    final rs =
        await db.query(tableName, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rs.isEmpty) return null;
    return Employee.fromMap(rs.first);
  }

  static Future<Employee?> getByCode(String code) async {
    await ensureTable();
    final db = await _db;
    final rs = await db.query(
      tableName,
      where: 'employee_code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rs.isEmpty) return null;
    return Employee.fromMap(rs.first);
  }

  static Future<bool> existsByCode(String code) async {
    await ensureTable();
    final db = await _db;
    final rs = await db.rawQuery(
        'SELECT 1 FROM $tableName WHERE employee_code = ? LIMIT 1', [code]);
    return rs.isNotEmpty;
  }

  static Future<List<Employee>> searchByName(String query) async {
    await ensureTable();
    final db = await _db;
    final rs = await db.query(
      tableName,
      where: 'full_name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'full_name COLLATE NOCASE ASC',
    );
    return rs.map(Employee.fromMap).toList();
  }

  static Future<List<Employee>> search(String q) async {
    await ensureTable();
    final db = await _db;
    final like = '%$q%';
    final rs = await db.query(
      tableName,
      where: 'full_name LIKE ? OR employee_code LIKE ?',
      whereArgs: [like, like],
      orderBy: 'full_name COLLATE NOCASE ASC',
    );
    return rowsToEmployees(rs);
  }

  static List<Employee> rowsToEmployees(List<Map<String, Object?>> rs) =>
      rs.map(Employee.fromMap).toList();

  // ───────────── Helpers ─────────────

  static Future<int> setBaseSalary(String id, double amount) async {
    return patch(id, {'base_salary': amount});
  }

  static Future<int> setStatus(String id, String status) async {
    return patch(id, {'status': status});
  }

  static Future<int> setPaymentMethod(String id, String method) async {
    return patch(id, {'payment_method': method});
  }

  static Future<int> setContractType(String id, EmployeeContractType type) {
    return patch(id, {'contract_type': type.name});
  }

  static Future<int> setWeeklyRate(String id, double? amount) {
    return patch(id, {'weekly_rate': amount});
  }

  static Future<int> setDailyRate(String id, double? amount) {
    return patch(id, {'daily_rate': amount});
  }

  static Future<int> setContractAmount(String id, double? amount) {
    return patch(id, {'contract_amount': amount});
  }

  static Future<int> setContractMeta(
    String id, {
    String? desc,
    String? status,
    String? dueDateIso,
    String? cycleAnchorIso,
  }) {
    return patch(id, {
      'contract_desc': desc,
      'contract_status': status,
      'contract_due_date': dueDateIso,
      'cycle_anchor': cycleAnchorIso,
    });
  }
}
