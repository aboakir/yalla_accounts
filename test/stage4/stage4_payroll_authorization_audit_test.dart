import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/employees/models/advance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/advance_database_service.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_periods_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late AuthSessionService session;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationGuard.disableInteractiveEnforcement();

    temp = await Directory.systemTemp.createTemp('payroll_auth_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(temp.path, 'authorization.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = AuthSessionService(databaseProvider: () async => db);

    await EmployeeDatabaseService.insert(Employee.fromMap({
      'id': 'auth-e1',
      'employee_code': 'AUTH-E1',
      'full_name': 'Payroll Authorization Employee',
      'hire_date': '2026-01-01',
      'created_at': '2026-01-01',
      'status': 'active',
      'base_salary': 1000,
      'contract_type': 'monthly',
    }));
  });
  tearDown(() async {
    AuthorizationGuard.disableInteractiveEnforcement();
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('payroll roles expose view separately from manage', () {
    expect(
      AuthorizationPolicy.forRole(RoleKeys.owner),
      contains(PermissionKeys.payrollManage),
    );
    expect(
      AuthorizationPolicy.forRole(RoleKeys.accountant),
      contains(PermissionKeys.payrollManage),
    );
    expect(
      AuthorizationPolicy.forRole(RoleKeys.manager),
      contains(PermissionKeys.payrollView),
    );
    expect(
      AuthorizationPolicy.forRole(RoleKeys.manager),
      isNot(contains(PermissionKeys.payrollManage)),
    );
    expect(
      AuthorizationPolicy.forRole(RoleKeys.viewer),
      isNot(contains(PermissionKeys.payrollView)),
    );
  });
  test('view-only payroll role is denied before financial writes', () async {
    await _assumeRole(session, RoleKeys.manager);
    AuthorizationGuard.enableInteractiveEnforcement();

    expect(await PayrollDatabaseService.listByMonth('2026-09'), isEmpty);

    Future<void> denied(Future<void> future) async {
      await expectLater(
        future,
        throwsA(
          predicate(
            (error) => error.toString().contains(
                  'Permission denied: ${PermissionKeys.payrollManage}',
                ),
          ),
        ),
      );
    }

    await denied(
      PayrollDatabaseService.accrue(
        employeeId: 'auth-e1',
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        accrualDate: DateTime(2026, 9, 30),
        gross: 1000,
      ).then((_) {}),
    );
    await denied(
      PayrollPeriodsService.lockPeriod(2026, 9, note: 'denied'),
    );
    await denied(
      AdvanceDatabaseService.insertAdvance(
        advance: Advance(
          id: 'AUTH-ADV-DENIED',
          employeeId: 'auth-e1',
          amount: 100,
          type: 'advance',
          date: DateTime(2026, 9, 1),
          method: 'cash',
        ),
        method: 'cash',
      ).then((_) {}),
    );

    expect(await db.query('payroll_runs'), isEmpty);
    expect(await db.query('employee_advances'), isEmpty);
    expect(await db.query('vouchers'), isEmpty);
    expect(await db.query('gl_entries'), isEmpty);
    final periodTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='salary_periods'",
    );
    expect(periodTable, isEmpty);
  });

  test('owner payroll writes create canonical audit evidence', () async {
    await _assumeRole(session, RoleKeys.owner);
    AuthorizationGuard.disableInteractiveEnforcement();
    final runId = await PayrollDatabaseService.accrue(
      employeeId: 'auth-e1',
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      accrualDate: DateTime(2026, 9, 30),
      gross: 1000,
    );

    final accrualAudit = await db.query(
      'app_audit_events',
      where: 'action=? AND entity_type=? AND entity_id=?',
      whereArgs: ['PAYROLL_ACCRUED', 'payroll_run', runId],
    );
    expect(accrualAudit, hasLength(1));
    expect(
        await db.query(
          'gl_entries',
          where: 'source=? AND source_id=?',
          whereArgs: ['PAYROLL_ACCRUAL', runId],
        ),
        hasLength(1));

    await PayrollDatabaseService.pay(
      runId: runId,
      amount: 400,
      date: DateTime(2026, 9, 30),
      method: 'cash',
    );
    final paymentVoucher = (await db.query(
      'vouchers',
      where: 'source=? AND source_id=?',
      whereArgs: ['PAYROLL_ENTITLEMENT', runId],
      limit: 1,
    ))
        .single;
    expect(
      await db.query(
        'app_audit_events',
        where: 'action=? AND entity_id=?',
        whereArgs: ['PAYMENT_VOUCHER_POSTED', paymentVoucher['id']],
      ),
      hasLength(1),
    );

    await EmployeeDatabaseService.insert(Employee.fromMap({
      'id': 'auth-e2',
      'employee_code': 'AUTH-E2',
      'full_name': 'Payroll Reverse Employee',
      'hire_date': '2026-01-01',
      'created_at': '2026-01-01',
      'status': 'active',
      'base_salary': 500,
      'contract_type': 'monthly',
    }));
    final reverseRunId = await PayrollDatabaseService.accrue(
      employeeId: 'auth-e2',
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 31),
      accrualDate: DateTime(2026, 10, 31),
      gross: 500,
    );
    await PayrollDatabaseService.reverseAccrual(
      reverseRunId,
      note: 'Authorization audit reversal',
    );

    expect(
      await db.query(
        'app_audit_events',
        where: 'action=? AND entity_id=?',
        whereArgs: ['PAYROLL_ACCRUAL_REVERSED', reverseRunId],
      ),
      hasLength(1),
    );
    expect(
      (await PayrollDatabaseService.getById(reverseRunId))!.status,
      'REVERSED',
    );
  });
}

Future<void> _assumeRole(AuthSessionService session, String role) async {
  await session.startPreviewSession(
    AppUser(
      id: 'payroll-$role',
      name: role,
      email: '',
      role: role,
      status: 'active',
      createdAt: DateTime.utc(2026, 9, 23),
    ),
    localUser: false,
  );
}
