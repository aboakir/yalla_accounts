// 📁 lib/core/services/db/tables/hr_tables.dart
import 'package:sqflite/sqflite.dart';

class HRTables {
  // 👥 إنشاء جداول الموارد البشرية
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createEmployeesTable(db);
    await _createAttendanceTable(db);
    await _createEmployeeAdvancesTable(db);
    await _createPayrollRunsTable(db);
    await _createPayrollPaymentsTable(db);
    await ensureSyncColumns(db);
  }

  static Future<void> ensureSyncColumns(DatabaseExecutor db) async {
    await _ensureColumn(db, 'payroll_runs', 'created_at', 'TEXT');
    await _ensureColumn(db, 'payroll_runs', 'attendance_snapshot', 'TEXT');
    await _ensureColumn(db, 'payroll_runs', 'entitlement_basis', 'TEXT');
    await _ensureColumn(db, 'payroll_payments', 'voucher_id', 'TEXT');
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (!info.any((row) => row['name']?.toString() == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  // 👤 جدول الموظفين
  static Future<void> _createEmployeesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        id TEXT PRIMARY KEY,
        full_name TEXT NOT NULL,
        employee_code TEXT NOT NULL,
        job_title TEXT NOT NULL,
        hire_date TEXT NOT NULL,
        phone TEXT NOT NULL,
        email TEXT NOT NULL,
        address TEXT NOT NULL,
        status TEXT NOT NULL,
        base_salary REAL NOT NULL,
        allowances REAL NOT NULL,
        deductions REAL NOT NULL,
        advances REAL NOT NULL,
        total_work_days INTEGER NOT NULL,
        total_hours REAL NOT NULL,
        absences INTEGER NOT NULL,
        late_days INTEGER NOT NULL,
        notes TEXT NOT NULL,
        photo_url TEXT,
        contract_url TEXT,
        last_salary_paid_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        payment_method TEXT NOT NULL,
        work_days_per_week INTEGER NOT NULL,
        hours_per_day INTEGER NOT NULL
      )
    ''');
  }

  // ⏰ جدول الحضور
  static Future<void> _createAttendanceTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance (
        id TEXT PRIMARY KEY,
        employeeId TEXT NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        checkIn TEXT,
        checkOut TEXT,
        hoursWorked REAL,
        notes TEXT
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attendance_emp_date ON attendance(employeeId, date);');
  }

  // 💰 جدول سلف الموظفين
  static Future<void> _createEmployeeAdvancesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS employee_advances(
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        date TEXT NOT NULL,
        method TEXT,
        note TEXT,
        gl_entry_id INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await _ensureEmployeeAdvancesIndexes(db);
  }

  static Future<void> _ensureEmployeeAdvancesIndexes(
      DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_emp ON employee_advances(employee_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_date ON employee_advances(date);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_type ON employee_advances(type);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_method ON employee_advances(method);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_gl ON employee_advances(gl_entry_id);');
  }

  // 📊 جدول عمليات الرواتب
  static Future<void> _createPayrollRunsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payroll_runs(
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        gross REAL NOT NULL,
        allowances REAL NOT NULL,
        deductions REAL NOT NULL,
        advance_applied REAL NOT NULL,
        net REAL NOT NULL,
        amount_paid REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        accrual_date TEXT NOT NULL,
        method TEXT,
        note TEXT,
        UNIQUE(employee_id, period_start, period_end)
      )
    ''');

    await _ensurePayrollRunsIndexes(db);
  }

  static Future<void> _ensurePayrollRunsIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payroll_employee ON payroll_runs(employee_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payroll_period ON payroll_runs(period_start, period_end);');
  }

  // 💵 جدول مدفوعات الرواتب
  static Future<void> _createPayrollPaymentsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payroll_payments(
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        method TEXT,
        note TEXT
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payroll_payments_run ON payroll_payments(run_id);');
  }

  // 🔄 ترقية الجداول
  static Future<void> onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 25) {
      await _createEmployeesTable(db);
      await _createAttendanceTable(db);
    }

    // v30+: تأكيد وجود جداول السلف والرواتب
    await _createEmployeeAdvancesTable(db);
    await _createPayrollRunsTable(db);
    await _createPayrollPaymentsTable(db);
  }

  // 🎯 واجهات الاستخدام
  static Future<List<Map<String, dynamic>>> getEmployees(
      DatabaseExecutor db) async {
    return await db.query('employees', orderBy: 'full_name');
  }

  static Future<Map<String, dynamic>> getEmployeeById(
      DatabaseExecutor db, String id) async {
    final result = await db.query(
      'employees',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty ? Map<String, dynamic>.from(result.first) : {};
  }

  static Future<void> markAttendance(
      DatabaseExecutor db, String employeeId, DateTime date) async {
    final existing = await db.query(
      'attendance',
      where: 'employeeId = ? AND date = ?',
      whereArgs: [employeeId, date.toIso8601String().split('T').first],
    );

    if (existing.isEmpty) {
      await db.insert('attendance', {
        'id': '${employeeId}_${date.toIso8601String().split('T').first}',
        'employeeId': employeeId,
        'date': date.toIso8601String().split('T').first,
        'status': 'PRESENT',
        'checkIn': DateTime.now().toIso8601String(),
        'hoursWorked': 8.0,
      });
    }
  }

  static Future<List<Map<String, dynamic>>> getEmployeeAttendance(
      DatabaseExecutor db,
      String employeeId,
      DateTime startDate,
      DateTime endDate) async {
    return await db.query(
      'attendance',
      where: 'employeeId = ? AND date BETWEEN ? AND ?',
      whereArgs: [
        employeeId,
        startDate.toIso8601String().split('T').first,
        endDate.toIso8601String().split('T').first,
      ],
      orderBy: 'date DESC',
    );
  }

  static Future<double> getEmployeeAdvancesTotal(
      DatabaseExecutor db, String employeeId) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit-l.credit),0) as total
      FROM gl_lines l JOIN accounts a ON a.id=l.account_id
      WHERE a.code = ?
    ''', ['1120.E$employeeId']);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  static Future<int> createPayrollRun(
      DatabaseExecutor db, Map<String, dynamic> data) async {
    return await db.insert('payroll_runs', data);
  }

  static Future<List<Map<String, dynamic>>> getPendingPayrollRuns(
      DatabaseExecutor db) async {
    return await db.query(
      'payroll_runs',
      where: 'status = ? OR amount_paid < net',
      whereArgs: ['PENDING'],
    );
  }
}
