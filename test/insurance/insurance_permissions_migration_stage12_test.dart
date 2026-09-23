import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String dbPath;
  late Database db;
  late AuthSessionService session;

  Future<int> countRows(String table) async {
    final row = (await db.rawQuery('SELECT COUNT(*) n FROM $table')).single;
    return (row['n'] as num).toInt();
  }

  Future<void> assumeRole(String role) async {
    await session.startPreviewSession(
      AppUser(
        id: 'stage12-$role',
        name: role,
        email: '',
        role: role,
        status: 'active',
        createdAt: DateTime.utc(2026, 9, 23),
      ),
      localUser: false,
    );
  }

  Future<void> reopen() async {
    await session.endEphemeralPreviewSession();
    AuthorizationGuard.disableInteractiveEnforcement();
    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();
    db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
    DatabaseMigration.useDatabaseForTesting(db);
    session = AuthSessionService(databaseProvider: () async => db);
    await assumeRole(RoleKeys.owner);
  }

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationGuard.disableInteractiveEnforcement();
    temp = await Directory.systemTemp.createTemp('insurance_stage12_');
    dbPath = '${temp.path}/stage12.db';
    db = await DatabaseMigration.initDatabase(pathOverride: dbPath);
    DatabaseMigration.useDatabaseForTesting(db);
    session = AuthSessionService(databaseProvider: () async => db);
    await assumeRole(RoleKeys.owner);
  });
  tearDown(() async {
    AuthorizationGuard.disableInteractiveEnforcement();
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('stage12 persists granular insurance permission matrix', () async {
    const keys = <String>{
      PermissionKeys.insuranceView,
      PermissionKeys.insuranceCrmManage,
      PermissionKeys.insuranceMasterDataManage,
      PermissionKeys.insurancePolicyPost,
      PermissionKeys.insuranceClaimManage,
      PermissionKeys.insuranceRenewalManage,
      PermissionKeys.insuranceFinanceManage,
      PermissionKeys.insuranceReportExport,
    };
    final stored = await db.query(
      'auth_permissions',
      columns: const ['permission_key'],
    );
    final storedKeys =
        stored.map((row) => row['permission_key'].toString()).toSet();
    expect(storedKeys.containsAll(keys), isTrue);

    final admin = AuthorizationPolicy.forRole(RoleKeys.admin);
    expect(admin.containsAll(keys), isTrue);
    final staff = AuthorizationPolicy.forRole(RoleKeys.staff);
    expect(staff, contains(PermissionKeys.insuranceView));
    expect(staff, contains(PermissionKeys.insuranceCrmManage));
    expect(staff, contains(PermissionKeys.insuranceClaimManage));
    expect(staff, contains(PermissionKeys.insuranceRenewalManage));
    expect(staff, isNot(contains(PermissionKeys.insuranceFinanceManage)));
    expect(
      staff,
      isNot(contains(PermissionKeys.insuranceMasterDataManage)),
    );

    final accountant = AuthorizationPolicy.forRole(RoleKeys.accountant);
    expect(accountant, contains(PermissionKeys.insuranceFinanceManage));
    expect(accountant, contains(PermissionKeys.insuranceReportExport));
    expect(accountant, isNot(contains(PermissionKeys.insuranceCrmManage)));
  });

  test('stage12 denies forbidden writes before creating rows', () async {
    await assumeRole(RoleKeys.viewer);
    AuthorizationGuard.enableInteractiveEnforcement();

    final companiesBefore = await countRows('insurance_companies');
    final suppliersBefore = await countRows('suppliers');
    await expectLater(
      InsuranceMasterDataService.createCompany(
        code: 'DENIED',
        name: 'Denied Insurance Company',
      ),
      throwsA(
        predicate(
          (error) => '$error'.contains(
            'Permission denied: ${PermissionKeys.insuranceMasterDataManage}',
          ),
        ),
      ),
    );
    expect(await countRows('insurance_companies'), companiesBefore);
    expect(await countRows('suppliers'), suppliersBefore);
  });

  test('stage12 staff CRM crosses RBAC but license still fails closed',
      () async {
    await assumeRole(RoleKeys.staff);
    AuthorizationGuard.enableInteractiveEnforcement();

    await expectLater(
      InsuranceCrmService.createProspect(
        name: 'Stage 12 Prospect',
        phone: '0599001212',
        city: 'Bethlehem',
      ),
      throwsA(
        predicate(
          (error) =>
              '$error'.contains('ACTIVATION_REQUIRED') &&
              !'$error'.contains('Permission denied'),
        ),
      ),
    );
    expect(await countRows('insurance_prospects'), 0);

    await expectLater(
      InsuranceMasterDataService.createCompany(
        code: 'STAFF-DENIED',
        name: 'Staff Denied Company',
      ),
      throwsA(
        predicate(
          (error) => '$error'.contains(
            'Permission denied: ${PermissionKeys.insuranceMasterDataManage}',
          ),
        ),
      ),
    );

    AuthorizationGuard.disableInteractiveEnforcement();
    final prospect = await InsuranceCrmService.createProspect(
      name: 'Stage 12 Prospect',
      phone: '0599001212',
      city: 'Bethlehem',
    );
    expect(prospect.name, 'Stage 12 Prospect');
    expect(
      await db.query(
        'insurance_prospects',
        where: 'id=?',
        whereArgs: [prospect.id],
      ),
      hasLength(1),
    );
  });

  test(
      'stage12 v85 reopen restores permissions without touching insurance data',
      () async {
    AuthorizationGuard.disableInteractiveEnforcement();
    final companyId = await db.insert('insurance_companies', {
      'code': 'MIG-STAGE12',
      'name': 'Stage 12 Migration Company',
      'default_commission_rate': 7.5,
      'is_active': 1,
      'created_at': DateTime.utc(2026, 9, 23).toIso8601String(),
      'updated_at': DateTime.utc(2026, 9, 23).toIso8601String(),
    });
    const key = PermissionKeys.insuranceCrmManage;
    await db.delete(
      'auth_role_permissions',
      where: 'permission_key=?',
      whereArgs: const [key],
    );
    await db.delete(
      'auth_permissions',
      where: 'permission_key=?',
      whereArgs: const [key],
    );

    await reopen();

    expect(
      await db.query(
        'auth_permissions',
        where: 'permission_key=?',
        whereArgs: const [key],
      ),
      hasLength(1),
    );
    final company = (await db.query(
      'insurance_companies',
      where: 'id=?',
      whereArgs: [companyId],
      limit: 1,
    ))
        .single;
    expect(company['code'], 'MIG-STAGE12');
    expect(company['name'], 'Stage 12 Migration Company');
    expect((company['default_commission_rate'] as num).toDouble(), 7.5);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
