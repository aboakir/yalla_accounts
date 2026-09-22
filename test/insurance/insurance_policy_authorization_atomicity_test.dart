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
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/services/insurance_policy_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late AuthSessionService session;
  late int companyId;
  late String productId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationGuard.disableInteractiveEnforcement();
    temp = await Directory.systemTemp.createTemp('insurance_policy_auth_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/authorization.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = AuthSessionService(databaseProvider: () async => db);
    await _assumeRole(session, RoleKeys.owner);
    companyId = await db.insert('insurance_companies', {
      'code': 'AUTH-INS',
      'name': 'Authorization Insurance Company',
      'default_commission_rate': 0,
      'is_active': 1,
      'created_at': DateTime.utc(2026, 9, 22).toIso8601String(),
      'updated_at': DateTime.utc(2026, 9, 22).toIso8601String(),
    });
    productId = 'AUTH-PRODUCT';
    await db.insert('insurance_products', {
      'id': productId,
      'company_id': companyId,
      'code': 'AUTH-COMP',
      'name': 'Authorization Comprehensive',
      'product_type': 'COMPREHENSIVE',
      'default_commission_rate': 0,
      'is_active': 1,
      'created_at': DateTime.utc(2026, 9, 22).toIso8601String(),
      'updated_at': DateTime.utc(2026, 9, 22).toIso8601String(),
    });
  });

  tearDown(() async {
    AuthorizationGuard.disableInteractiveEnforcement();
    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('insurance policy posting permission is granted only to finance roles',
      () async {
    for (final role in const [
      RoleKeys.owner,
      RoleKeys.admin,
      RoleKeys.manager,
      RoleKeys.accountant,
    ]) {
      expect(
        AuthorizationPolicy.forRole(role),
        contains(PermissionKeys.insurancePolicyPost),
        reason: '$role must be able to issue an insurance policy',
      );
    }
    for (final role in const [
      RoleKeys.staff,
      RoleKeys.viewer,
      RoleKeys.employee,
      RoleKeys.cashier,
    ]) {
      expect(
        AuthorizationPolicy.forRole(role),
        isNot(contains(PermissionKeys.insurancePolicyPost)),
        reason: '$role must not be able to issue an insurance policy',
      );
    }

    final storedRoles = await db.query(
      'auth_role_permissions',
      columns: const ['role_key'],
      where: 'permission_key=?',
      whereArgs: const [PermissionKeys.insurancePolicyPost],
      orderBy: 'role_key',
    );
    expect(
      storedRoles.map((row) => row['role_key']),
      unorderedEquals(const [
        RoleKeys.owner,
        RoleKeys.admin,
        RoleKeys.manager,
        RoleKeys.accountant,
      ]),
    );

    final permit = await AuthorizationGuard.issuePermit(
      PermissionKeys.insurancePolicyPost,
    );
    expect(
      () => AuthorizationGuard.consumePermit(
        permit,
        PermissionKeys.receiptCreate,
      ),
      throwsStateError,
    );
    AuthorizationGuard.consumePermit(
      permit,
      PermissionKeys.insurancePolicyPost,
    );
    expect(
      () => AuthorizationGuard.consumePermit(
        permit,
        PermissionKeys.insurancePolicyPost,
      ),
      throwsStateError,
    );
  });

  test('already-v85 reopen refreshes the insurance posting permission',
      () async {
    await db.delete(
      'auth_role_permissions',
      where: 'permission_key=?',
      whereArgs: const [PermissionKeys.insurancePolicyPost],
    );
    await db.delete(
      'auth_permissions',
      where: 'permission_key=?',
      whereArgs: const [PermissionKeys.insurancePolicyPost],
    );
    expect(
      await _count(
        db,
        'auth_permissions',
        where: 'permission_key=?',
        whereArgs: const [PermissionKeys.insurancePolicyPost],
      ),
      0,
    );

    await session.endEphemeralPreviewSession();
    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/authorization.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = AuthSessionService(databaseProvider: () async => db);
    await _assumeRole(session, RoleKeys.owner);

    expect(
      await _count(
        db,
        'auth_permissions',
        where: 'permission_key=?',
        whereArgs: const [PermissionKeys.insurancePolicyPost],
      ),
      1,
    );
    final storedRoles = await db.query(
      'auth_role_permissions',
      columns: const ['role_key'],
      where: 'permission_key=?',
      whereArgs: const [PermissionKeys.insurancePolicyPost],
    );
    expect(
      storedRoles.map((row) => row['role_key']),
      unorderedEquals(const [
        RoleKeys.owner,
        RoleKeys.admin,
        RoleKeys.manager,
        RoleKeys.accountant,
      ]),
    );
  });

  test('wizard policy issuance is denied before any canonical write', () async {
    await _assumeRole(session, RoleKeys.staff);
    AuthorizationGuard.enableInteractiveEnforcement();
    final sequenceBefore = await _policySequence(db);
    final suppliersBefore = await _count(db, 'suppliers');
    final partiesBefore = await _count(db, 'parties');

    await expectLater(
      InsurancePolicyService.savePolicyDraft(
        _chequeDraft(
          companyId,
          productId,
          operationId: 'AUTH-WIZARD-DENIED',
        ),
        database: db,
      ),
      throwsA(
        predicate(
          (error) => '$error'.contains(
            'Permission denied: ${PermissionKeys.insurancePolicyPost}',
          ),
        ),
      ),
    );

    expect(await _count(db, 'insurance_policies'), 0);
    expect(await _count(db, 'clients'), 0);
    expect(await _count(db, 'vehicles'), 0);
    expect(await _count(db, 'suppliers'), suppliersBefore);
    expect(await _count(db, 'parties'), partiesBefore);
    expect(await _count(db, 'gl_entries'), 0);
    expect(await _count(db, 'cheques'), 0);
    expect(await _policySequence(db), sequenceBefore);
    final company = (await db.query(
      'insurance_companies',
      where: 'id=?',
      whereArgs: [companyId],
      limit: 1,
    ))
        .single;
    expect(company['party_id'], isNull);
    expect(company['supplier_id'], isNull);
  });

  test('direct financial policy posting is denied before GL or numbering',
      () async {
    await _assumeRole(session, RoleKeys.viewer);
    AuthorizationGuard.enableInteractiveEnforcement();
    final sequenceBefore = await _policySequence(db);

    await expectLater(
      InsuranceFinancialService.postPolicy(
        InsurancePolicyPostingCommand(
          operationId: 'AUTH-DIRECT-DENIED',
          policyNumber: 'AUTH-DIRECT-001',
          clientId: 1,
          insuredPartyId: 'CUSTOMER:1',
          companyId: companyId.toString(),
          insurerPartyId: 'SUPPLIER:1',
          insurerSupplierId: 1,
          startDate: DateTime.utc(2026, 9, 22),
          endDate: DateTime.utc(2027, 9, 21),
          postingDate: DateTime.utc(2026, 9, 22),
          purchasePrice: 2000,
          salePrice: 2400,
        ),
        database: db,
      ),
      throwsA(
        predicate(
          (error) => '$error'.contains(
            'Permission denied: ${PermissionKeys.insurancePolicyPost}',
          ),
        ),
      ),
    );

    expect(await _count(db, 'insurance_policies'), 0);
    expect(await _count(db, 'gl_entries'), 0);
    expect(await _count(db, 'gl_lines'), 0);
    expect(await _policySequence(db), sequenceBefore);
  });

  test(
      'receipt-side failure rolls back policy cheque GL identities and numbering',
      () async {
    final sequenceBefore = await _policySequence(db);
    await db.execute('''
      CREATE TRIGGER phase10_abort_receipt_header
      BEFORE INSERT ON receipt_headers
      BEGIN
        SELECT RAISE(ABORT, 'forced failure after receipt-side rows');
      END
    ''');
    final draft = _chequeDraft(
      companyId,
      productId,
      operationId: 'AUTH-ATOMIC-ROLLBACK',
      insuredPhone: '0598555010',
      vehiclePlate: 'AUTH-ROLLBACK-10',
    );

    await expectLater(
      InsurancePolicyService.savePolicyDraft(draft, database: db),
      throwsA(
        predicate(
          (error) =>
              '$error'.contains('forced failure after receipt-side rows'),
        ),
      ),
    );

    expect(await _count(db, 'insurance_policies'), 0);
    expect(
      await _count(
        db,
        'clients',
        where: 'phone=?',
        whereArgs: const ['0598555010'],
      ),
      0,
    );
    expect(
      await _count(
        db,
        'parties',
        where: 'display_name=?',
        whereArgs: const ['Atomic Insurance Customer'],
      ),
      0,
    );
    expect(
      await _count(
        db,
        'vehicles',
        where: 'normalized_number=?',
        whereArgs: const ['AUTHROLLBACK10'],
      ),
      0,
    );
    expect(
      await _count(
        db,
        'suppliers',
        where: 'name=?',
        whereArgs: const ['Authorization Insurance Company'],
      ),
      0,
    );
    final companyAfterFailure = (await db.query(
      'insurance_companies',
      where: 'id=?',
      whereArgs: [companyId],
      limit: 1,
    ))
        .single;
    expect(companyAfterFailure['party_id'], isNull);
    expect(companyAfterFailure['supplier_id'], isNull);
    expect(await _count(db, 'cheques'), 0);
    expect(await _count(db, 'cheque_events'), 0);
    expect(await _count(db, 'payments'), 0);
    expect(await _count(db, 'insurance_policy_payments'), 0);
    expect(await _count(db, 'receipt_headers'), 0);
    expect(await _count(db, 'receipt_instruments'), 0);
    expect(await _count(db, 'receipt_requests'), 0);
    expect(await _count(db, 'insurance_financial_events'), 0);
    expect(await _count(db, 'gl_entries'), 0);
    expect(await _count(db, 'gl_lines'), 0);
    expect(await _policySequence(db), sequenceBefore);

    await db.execute('DROP TRIGGER phase10_abort_receipt_header');
    final policyId = await InsurancePolicyService.savePolicyDraft(
      draft,
      database: db,
    );
    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: [policyId],
      limit: 1,
    ))
        .single;
    final receipt = (await db.query('receipt_headers', limit: 1)).single;
    final cheque = (await db.query('cheques', limit: 1)).single;
    expect(policy['document_number'], 'POL-0001');
    expect(receipt['receipt_number'], 1);
    expect(cheque['cheque_no'], 'AUTH-CHQ-001');
    expect(await _count(db, 'gl_entries'), 2);
  });
}

Future<void> _assumeRole(AuthSessionService session, String role) async {
  await session.startPreviewSession(
    AppUser(
      id: 'insurance-$role',
      name: role,
      email: '',
      role: role,
      status: 'active',
      createdAt: DateTime.utc(2026, 9, 22),
    ),
    localUser: false,
  );
}

PolicyDraft _chequeDraft(
  int companyId,
  String productId, {
  required String operationId,
  String insuredPhone = '0598555001',
  String vehiclePlate = 'AUTH-VEHICLE-01',
}) {
  final draft = PolicyDraft()
    ..operationId = operationId
    ..policyNumber = 'INSURER-$operationId'
    ..postingDate = DateTime.utc(2026, 9, 22)
    ..vehiclePlate = vehiclePlate
    ..vehicleMake = 'Toyota'
    ..vehicleModelYear = '2026'
    ..engineCc = '1800'
    ..engineNumber = 'AUTH-ENGINE-01'
    ..chassisNumber = 'AUTH-CHASSIS-01'
    ..insuredName = 'Atomic Insurance Customer'
    ..insuredPhone = insuredPhone
    ..insuranceCompanyId = companyId
    ..companyName = 'Authorization Insurance Company'
    ..productId = productId
    ..coverageType = 'COMPREHENSIVE'
    ..startDate = DateTime.utc(2026, 9, 22)
    ..endDate = DateTime.utc(2027, 9, 21)
    ..buyPrice = 2000
    ..sellPrice = 2400
    ..notes = 'Authorization and atomicity regression';
  draft.payment.type = PolicyPaymentPlanType.chequesOnly;
  draft.payment.cheques.add(
    PolicyChequeItem()
      ..issueDate = DateTime.utc(2026, 9, 22)
      ..dueDate = DateTime.utc(2026, 12, 22)
      ..amount = 2400
      ..bankName = 'Authorization Bank'
      ..drawerName = 'Atomic Insurance Customer'
      ..chequeNumber = 'AUTH-CHQ-001',
  );
  return draft;
}

Future<int> _count(
  Database db,
  String table, {
  String? where,
  List<Object?>? whereArgs,
}) async {
  final rows = await db.query(
    table,
    columns: const ['COUNT(*) AS n'],
    where: where,
    whereArgs: whereArgs,
  );
  return (rows.single['n'] as num).toInt();
}

Future<int> _policySequence(Database db) async {
  final rows = await db.query(
    'document_sequences',
    columns: const ['next_value'],
    where: 'document_type=?',
    whereArgs: const ['INSURANCE_POLICY'],
    limit: 1,
  );
  return (rows.single['next_value'] as num).toInt();
}
