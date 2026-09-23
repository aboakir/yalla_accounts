import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/employees/models/advance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/advance_database_service.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_periods_service.dart';
import 'package:yalla_accounts/features/employees/services/salary_database_service.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Stage 4 hard payroll financial gate', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('payroll_hard_gate_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'gate.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'payroll-hard-owner');

    Future<void> employee(String id, double salary) async {
      await EmployeeDatabaseService.insert(Employee.fromMap({
        'id': id,
        'employee_code': id.toUpperCase(),
        'full_name': 'Employee $id',
        'hire_date': '2026-01-01',
        'created_at': '2026-01-01',
        'status': 'active',
        'base_salary': salary,
        'contract_type': 'monthly',
      }));
    }

    Future<Map<String, Object?>> accrueAttempt(String employeeId) async {
      try {
        final id = await PayrollDatabaseService.accrue(
          employeeId: employeeId,
          periodStart: DateTime(2026, 9, 1),
          periodEnd: DateTime(2026, 9, 30),
          accrualDate: DateTime(2026, 9, 30),
          gross: employeeId == 'e2' ? 500 : 1000,
        );
        return {'id': id};
      } catch (error) {
        return {'error': error};
      }
    }

    try {
      await employee('e1', 1000);
      await employee('e2', 500);
      await employee('e3', 500);

      await expectLater(
        PayrollDatabaseService.accrue(
          employeeId: 'e1',
          periodStart: DateTime(2026, 8, 1),
          periodEnd: DateTime(2026, 8, 31),
          accrualDate: DateTime(2026, 8, 31),
          gross: 100,
          deductions: 101,
        ),
        throwsArgumentError,
      );

      final attempts = await Future.wait([
        accrueAttempt('e1'),
        accrueAttempt('e1'),
      ]);
      final successful =
          attempts.where((result) => result.containsKey('id')).toList();
      final rejected =
          attempts.where((result) => result.containsKey('error')).toList();
      expect(successful, hasLength(1));
      expect(rejected, hasLength(1));
      expect(
          await db
              .query('payroll_runs', where: 'employee_id=?', whereArgs: ['e1']),
          hasLength(1));
      final run1 = successful.single['id']! as String;
      await PayrollDatabaseService.pay(
        runId: run1,
        amount: 400,
        date: DateTime(2026, 9, 30),
        method: 'cash',
      );
      var state = (await PayrollDatabaseService.getById(run1))!;
      expect(state.amountPaid, 400);
      expect(state.status, 'ACCRUED');

      await PayrollDatabaseService.pay(
        runId: run1,
        amount: 600,
        date: DateTime(2026, 9, 30),
        method: 'cash',
      );
      state = (await PayrollDatabaseService.getById(run1))!;
      expect(state.amountPaid, 1000);
      expect(state.status, 'PAID');

      final run1Vouchers = await db.query(
        'vouchers',
        where: 'source=? AND source_id=?',
        whereArgs: ['PAYROLL_ENTITLEMENT', run1],
        orderBy: 'created_at ASC, id ASC',
      );
      expect(run1Vouchers, hasLength(2));
      final secondVoucher = run1Vouchers
          .firstWhere((row) => (row['amount'] as num).toDouble() == 600);
      await VoucherPaymentService.reverseVoucher(
        secondVoucher['id']!.toString(),
        reason: 'Stage 4 reversal gate',
        database: db,
      );
      state = (await PayrollDatabaseService.getById(run1))!;
      expect(state.amountPaid, 400);
      expect(state.status, 'ACCRUED');
      final salaryAfterReverse = await SalaryDatabaseService.getSalary(
        employeeId: 'e1',
        month: '2026-09',
      );
      expect(salaryAfterReverse!.paid, 400);
      expect(salaryAfterReverse.due, 600);

      final audit = await db.query(
        'app_audit_events',
        where: 'action=? AND entity_id=?',
        whereArgs: [
          'PAYMENT_VOUCHER_REVERSED',
          secondVoucher['id']!.toString(),
        ],
      );
      expect(audit, isNotEmpty);

      final run2 = await PayrollDatabaseService.accrue(
        employeeId: 'e2',
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        accrualDate: DateTime(2026, 9, 30),
        gross: 500,
      );
      Future<Object?> payAttempt() async {
        try {
          await PayrollDatabaseService.pay(
            runId: run2,
            amount: 500,
            date: DateTime(2026, 9, 30),
            method: 'cash',
          );
          return null;
        } catch (error) {
          return error;
        }
      }

      final paymentAttempts = await Future.wait([
        payAttempt(),
        payAttempt(),
      ]);
      expect(paymentAttempts.where((error) => error == null), hasLength(1));
      expect(paymentAttempts.where((error) => error != null), hasLength(1));

      final run2State = (await PayrollDatabaseService.getById(run2))!;
      expect(run2State.amountPaid, 500);
      expect(run2State.status, 'PAID');
      expect(
        await db.query(
          'vouchers',
          where: 'source=? AND source_id=? AND status<>?',
          whereArgs: ['PAYROLL_ENTITLEMENT', run2, 'REVERSED'],
        ),
        hasLength(1),
      );
      final run3 = await PayrollDatabaseService.accrue(
        employeeId: 'e3',
        periodStart: DateTime(2026, 10, 1),
        periodEnd: DateTime(2026, 10, 31),
        accrualDate: DateTime(2026, 10, 31),
        gross: 500,
      );
      await PayrollPeriodsService.lockPeriod(2026, 10, note: 'close gate');
      await expectLater(
        PayrollDatabaseService.reverseAccrual(run3),
        throwsStateError,
      );
      expect((await PayrollDatabaseService.getById(run3))!.status, 'ACCRUED');

      await AdvanceDatabaseService.insertAdvance(
        advance: Advance(
          id: 'ADV-E1-300',
          employeeId: 'e1',
          amount: 300,
          type: 'advance',
          date: DateTime(2026, 11, 1),
          method: 'cash',
        ),
        method: 'cash',
      );
      final run4 = await PayrollDatabaseService.accrue(
        employeeId: 'e1',
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        accrualDate: DateTime(2026, 11, 30),
        gross: 1000,
      );
      final run4State = (await PayrollDatabaseService.getById(run4))!;
      expect(run4State.advanceApplied, 300);
      expect(run4State.net, 700);

      Future<double> accountBalance(String code) async {
        final row = (await db.rawQuery(
          'SELECT COALESCE(SUM(l.debit-l.credit),0) n '
          'FROM gl_lines l JOIN accounts a ON a.id=l.account_id '
          'WHERE a.code=?',
          [code],
        ))
            .single;
        return (row['n'] as num).toDouble();
      }

      expect(await accountBalance('1120.Ee1'), 0);
      expect(await accountBalance('5100'), 3000);

      final unbalanced = await db.rawQuery(
        'SELECT entry_id FROM gl_lines GROUP BY entry_id '
        'HAVING ABS(SUM(debit-credit)) > 0.001',
      );
      expect(unbalanced, isEmpty);

      final activePayrollPaid = (await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) total FROM vouchers "
        "WHERE source='PAYROLL_ENTITLEMENT' "
        "AND UPPER(COALESCE(status,'POSTED')) <> 'REVERSED'",
      ))
          .single['total'] as num;
      expect(activePayrollPaid.toDouble(), 900);
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}
