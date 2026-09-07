// 📁 lib/features/employees/services/salary_payment_database_service.dart
//
// Stage 4: legacy salary_payments is read-only compatibility data.
// All new salary payments must be PAYMENT vouchers linked to payroll entitlements.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/employees/models/salary_payment.dart';

class SalaryPaymentDatabaseService {
  static const String _table = 'salary_payments';
  static Future<Database> get _db async => DBService.database;

  static Future<void> ensureTable() async {
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        employeeId TEXT NOT NULL,
        periodStart TEXT NOT NULL,
        periodEnd TEXT NOT NULL,
        baseSalary REAL,
        allowances REAL,
        deductions REAL,
        advances REAL,
        totalPaid REAL,
        method TEXT,
        paymentDate TEXT,
        note TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_salary_pay_emp ON $_table(employeeId);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_salary_pay_date ON $_table(paymentDate);',
    );
  }

  @Deprecated(
      'Salary payments must be payment vouchers linked to payroll entitlements')
  static Future<void> insert(SalaryPayment payment) async {
    throw StateError(
      'Legacy salary_payments writes are disabled. Use a payroll payment voucher.',
    );
  }

  @Deprecated(
      'Salary payments must be payment vouchers linked to payroll entitlements')
  static Future<void> update(SalaryPayment payment) async {
    throw StateError(
      'Legacy salary_payments writes are disabled. Use a payroll payment voucher.',
    );
  }

  @Deprecated(
      'Salary payments must be payment vouchers linked to payroll entitlements')
  static Future<void> delete(String id) async {
    throw StateError(
      'Legacy salary_payments writes are disabled. Reverse the payment voucher instead.',
    );
  }

  static Future<List<SalaryPayment>> getByEmployee(String employeeId) async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'employeeId = ?',
      whereArgs: [employeeId],
      orderBy: 'paymentDate DESC, id DESC',
    );
    return rows.map(SalaryPayment.fromMap).toList();
  }

  static Future<List<SalaryPayment>> getByDateRange(
    DateTime from,
    DateTime to,
  ) async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'paymentDate BETWEEN ? AND ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'paymentDate DESC, id DESC',
    );
    return rows.map(SalaryPayment.fromMap).toList();
  }

  static Future<List<SalaryPayment>> getAll() async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query(_table, orderBy: 'paymentDate DESC, id DESC');
    return rows.map(SalaryPayment.fromMap).toList();
  }
}
