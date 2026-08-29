// 📁 lib/features/employees/services/employee_service.dart
//
// EmployeeService — موحّد على DBService (بدون أي بيانات وهمية)
// - يستخدم DBService فقط.
// - يسجّل الحضور في جدول attendance (date: DateTime، checkIn/out: String? ISO).
// - يسجّل دفعات الرواتب في salary_payments.

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';

// حضور
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart'
    as attendance_db;

// دفعات رواتب
import 'package:yalla_accounts/features/employees/services/salary_payment_database_service.dart'
    as salary_pay_db;

class EmployeeService {
  static Future<Database> get _db async => DBService.database;

  static Future<void> ensureTable() async {
    final db = await _db;
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

  // -------- CRUD موظفين --------
  static Future<void> addEmployee(Employee employee) async {
    await ensureTable();
    final db = await _db;
    final emp = employee.id.isEmpty
        ? employee.copyWith(id: const Uuid().v4())
        : employee;

    await db.insert(
      'employees',
      emp.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Employee>> getAllEmployees() async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query('employees', orderBy: 'full_name ASC');
    return rows.map(Employee.fromMap).toList();
  }

  static Future<Employee?> getEmployeeById(String id) async {
    await ensureTable();
    final db = await _db;
    final rows =
        await db.query('employees', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Employee.fromMap(rows.first);
  }

  static Future<void> updateEmployee(Employee employee) async {
    await ensureTable();
    final db = await _db;
    await db.update('employees', employee.toMap(),
        where: 'id = ?', whereArgs: [employee.id]);
  }

  static Future<void> deleteEmployee(String id) async {
    await ensureTable();
    final db = await _db;
    await db.delete('employees', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> updateStatus(String employeeId, String newStatus) async {
    await ensureTable();
    final db = await _db;
    await db.update('employees', {'status': newStatus},
        where: 'id = ?', whereArgs: [employeeId]);
  }

  // -------- حضور --------
  /// تسجيل حضور/غياب:
  /// - date: DateTime (كما يتوقع الموديل)
  /// - checkIn/checkOut: نحولهما إلى ISO نصي لأن الموديل يتوقع String?
  static Future<void> recordAttendance({
    required String employeeId,
    required DateTime date,
    required bool isPresent,
    double? hoursWorked,
    bool isLate = false,
    DateTime? checkIn,
    DateTime? checkOut,
    String? note,
  }) async {
    // تأكيد جدول attendance
    await attendance_db.AttendanceDatabaseService.createTable(await _db);

    final a = Attendance(
      id: const Uuid().v4(),
      employeeId: employeeId,
      date: date, // ✅ DateTime
      status: isPresent ? 'حضور' : 'غياب',
      checkIn: checkIn?.toIso8601String(), // ✅ String?
      checkOut: checkOut?.toIso8601String(), // ✅ String?
      hoursWorked: hoursWorked ?? 0.0,
      notes: [
        if (isLate) 'تأخير',
        if (note != null && note.trim().isNotEmpty) note.trim(),
      ].join(isLate && note != null && note.trim().isNotEmpty ? ' • ' : ''),
    );

    await attendance_db.AttendanceDatabaseService.insertAttendance(a);
  }

  // -------- رواتب --------
  static Future<void> paySalary({
    required String employeeId,
    required double amount,
    required DateTime payDate,
    String? method,
    String? note,
  }) async {
    await salary_pay_db.SalaryPaymentDatabaseService.ensureTable();
    final db = await _db;

    await db.insert(
      'salary_payments',
      {
        'id': const Uuid().v4(),
        'employeeId': employeeId,
        'totalPaid': amount,
        'method': method,
        'paymentDate': payDate.toIso8601String(),
        'note': note,
        // باقي الأعمدة (الفترة/البدلات/الاستقطاعات) تظل NULL إن ما تم تزويدها
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.update(
      'employees',
      {'last_salary_paid_date': payDate.toIso8601String()},
      where: 'id = ?',
      whereArgs: [employeeId],
    );
  }

  static Future<List<Map<String, dynamic>>> getSalaryPayments(
      String employeeId) async {
    await salary_pay_db.SalaryPaymentDatabaseService.ensureTable();
    final db = await _db;
    return db.query(
      'salary_payments',
      where: 'employeeId = ?',
      whereArgs: [employeeId],
      orderBy: 'paymentDate DESC, id DESC',
    );
  }
}
