import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/insurance_commercial_tables.dart';
import 'package:yalla_accounts/core/services/document_number_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';

import '../support/accounting_session.dart';

const _phase10FeatureKey = 'insurance_phase10_financial_bridge_v85';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String path;
  Database? db;
  AuthSessionService? session;
  const ownerId = 'phase10-compat-owner';
  late int clientId;
  late String clientPartyId;
  late int supplierId;
  late String supplierPartyId;
  late String companyId;

  Future<void> beginSession() async {
    final users = await db!.query(
      'users',
      where: 'id=?',
      whereArgs: const [ownerId],
      limit: 1,
    );
    if (users.isEmpty) {
      session = await startAccountingSession(db!, ownerId);
      final now = DateTime.now().toIso8601String();
      await db!.update('owner_bootstrap_state', {
        'status': 'COMPLETED',
        'owner_user_id': ownerId,
        'completed_at': now,
        'updated_at': now,
      });
      return;
    }
    final createdAt = DateTime.tryParse(
          users.single['created_at']?.toString() ?? '',
        ) ??
        DateTime.now();
    final current = AuthSessionService(databaseProvider: () async => db!);
    await current.createSession(
      AppUser(
        id: ownerId,
        name: ownerId,
        email: '',
        role: 'owner',
        status: 'active',
        createdAt: createdAt,
      ),
    );
    session = current;
  }

  Future<void> endSession() async {
    final current = session;
    session = null;
    if (current != null) await current.endEphemeralPreviewSession();
  }

  Future<void> reopen() async {
    await endSession();
    DatabaseMigration.useDatabaseForTesting(null);
    await db!.close();
    db = await DatabaseMigration.initDatabase(pathOverride: path);
    DatabaseMigration.useDatabaseForTesting(db);
    await beginSession();
  }

  InsurancePolicyPostingCommand command({
    required String operationId,
    required String policyNumber,
    String? documentNumber,
  }) {
    return InsurancePolicyPostingCommand(
      operationId: operationId,
      policyNumber: policyNumber,
      documentNumber: documentNumber,
      clientId: clientId,
      insuredPartyId: clientPartyId,
      companyId: companyId,
      insurerPartyId: supplierPartyId,
      insurerSupplierId: supplierId,
      startDate: DateTime.utc(2026, 9, 22),
      endDate: DateTime.utc(2027, 9, 21),
      postingDate: DateTime.utc(2026, 9, 22),
      purchasePrice: 2000,
      salePrice: 2400,
      createdBy: 'phase10-compat-owner',
    );
  }

  Future<int> count(String table) async {
    return ((await db!.rawQuery('SELECT COUNT(*) n FROM $table')).single['n']
            as num)
        .toInt();
  }

  Future<int> nextPolicyDocumentValue() async {
    return ((await db!.query(
      'document_sequences',
      columns: const ['next_value'],
      where: 'document_type=?',
      whereArgs: const ['INSURANCE_POLICY'],
      limit: 1,
    ))
            .single['next_value'] as num)
        .toInt();
  }

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('phase10_doc_compat_');
    path = '${temp.path}/compatibility.db';
    db = await DatabaseMigration.initDatabase(pathOverride: path);
    DatabaseMigration.useDatabaseForTesting(db);
    await beginSession();

    clientId = await db!.insert('clients', {
      'name': 'Compatibility Customer',
      'type': 'individual',
      'phone': '0599000042',
    });
    clientPartyId = (await db!.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['CUSTOMER', clientId.toString()],
      limit: 1,
    ))
        .single['party_id']
        .toString();
    await db!.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': DateTime.now().toIso8601String(),
    });

    supplierId = await db!.insert('suppliers', {
      'name': 'Compatibility Insurance Company',
      'pid': 'S-PHASE10-COMPAT',
    });
    supplierPartyId = (await db!.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['SUPPLIER', supplierId.toString()],
      limit: 1,
    ))
        .single['party_id']
        .toString();
    final now = DateTime.now().toIso8601String();
    companyId = (await db!.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'PHASE10-COMPAT',
      'name': 'Compatibility Insurance Company',
      'default_commission_rate': 0.0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    }))
        .toString();
    await db!.insert('party_roles', {
      'party_id': supplierPartyId,
      'role': 'INSURANCE_COMPANY',
      'legacy_id': companyId,
      'created_at': now,
    });
  });

  tearDown(() async {
    await endSession();
    DatabaseMigration.useDatabaseForTesting(null);
    if (db?.isOpen == true) await db!.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'already-v85 compatibility backfills a legacy document once and exact '
    'retry lazily stores its fingerprint',
    () async {
      final originalCommand = command(
        operationId: 'LEGACY-V85-OP',
        policyNumber: 'LEGACY-V85-POLICY',
      );
      final original = await InsuranceFinancialService.postPolicy(
        originalCommand,
        database: db,
      );
      expect(original.documentNumber, 'POL-0001');
      expect(await count('gl_entries'), greaterThan(0));
      final originalGlCount = await count('gl_entries');

      await db!.update(
        'insurance_policies',
        {'document_number': null, 'posting_request_json': null},
        where: 'id=?',
        whereArgs: [original.policyId],
      );
      await db!.update(
        'document_sequences',
        {'next_value': 1},
        where: 'document_type=?',
        whereArgs: const ['INSURANCE_POLICY'],
      );
      await db!.delete(
        'schema_feature_migrations',
        where: 'feature_key=?',
        whereArgs: const [_phase10FeatureKey],
      );

      await reopen();

      final migrated = (await db!.query(
        'insurance_policies',
        where: 'id=?',
        whereArgs: [original.policyId],
        limit: 1,
      ))
          .single;
      expect(migrated['document_number'], 'POL-0001');
      expect(migrated['posting_request_json'], isNull);
      expect(await nextPolicyDocumentValue(), 2);

      final marker = (await db!.query(
        'schema_feature_migrations',
        where: 'feature_key=?',
        whereArgs: const [_phase10FeatureKey],
        limit: 1,
      ))
          .single;
      expect(marker['from_schema_version'], 85);

      final retry = await InsuranceFinancialService.postPolicy(
        originalCommand,
        database: db,
      );
      expect(retry.wasExisting, isTrue);
      expect(retry.policyId, original.policyId);
      expect(retry.documentNumber, 'POL-0001');
      expect(retry.glEntryId, original.glEntryId);
      expect(await count('gl_entries'), originalGlCount);
      expect(
        (await db!.query(
          'insurance_policies',
          columns: const ['posting_request_json'],
          where: 'id=?',
          whereArgs: [original.policyId],
        ))
            .single['posting_request_json'],
        isNotNull,
      );

      final appliedAt = marker['applied_at'];
      await reopen();
      final markers = await db!.query(
        'schema_feature_migrations',
        where: 'feature_key=?',
        whereArgs: const [_phase10FeatureKey],
      );
      expect(markers, hasLength(1));
      expect(markers.single['applied_at'], appliedAt);
      expect(await nextPolicyDocumentValue(), 2);
      expect(
        (await db!.query(
          'insurance_policies',
          columns: const ['document_number'],
          where: 'id=?',
          whereArgs: [original.policyId],
        ))
            .single['document_number'],
        'POL-0001',
      );
    },
  );

  test('compatibility repairs a stale sequence past the highest POL number',
      () async {
    final posted = await InsuranceFinancialService.postPolicy(
      command(
        operationId: 'STALE-SEQUENCE-OP',
        policyNumber: 'STALE-SEQUENCE-POLICY',
        documentNumber: 'POL-0042',
      ),
      database: db,
    );
    expect(posted.documentNumber, 'POL-0042');

    await db!.update(
      'document_sequences',
      {'next_value': 2},
      where: 'document_type=?',
      whereArgs: const ['INSURANCE_POLICY'],
    );
    await InsuranceCommercialTables.ensurePhase10Compatibility(db!);

    expect(await nextPolicyDocumentValue(), 43);
    expect(
      await DocumentNumberService.nextOn(
        db!,
        documentType: 'INSURANCE_POLICY',
      ),
      'POL-0043',
    );
    expect(await nextPolicyDocumentValue(), 44);
  });

  test('a supplied POL number advances the next automatic policy document',
      () async {
    final supplied = await InsuranceFinancialService.postPolicy(
      command(
        operationId: 'SUPPLIED-DOCUMENT-OP',
        policyNumber: 'SUPPLIED-DOCUMENT-POLICY',
        documentNumber: 'POL-0100',
      ),
      database: db,
    );
    expect(supplied.documentNumber, 'POL-0100');
    expect(await nextPolicyDocumentValue(), 101);

    final automatic = await InsuranceFinancialService.postPolicy(
      command(
        operationId: 'AUTOMATIC-DOCUMENT-OP',
        policyNumber: 'AUTOMATIC-DOCUMENT-POLICY',
      ),
      database: db,
    );
    expect(automatic.documentNumber, 'POL-0101');
    expect(await nextPolicyDocumentValue(), 102);
  });

  test('policy and document uniqueness is normalized and case-insensitive',
      () async {
    await InsuranceFinancialService.postPolicy(
      command(
        operationId: 'NORMALIZED-KEY-1',
        policyNumber: 'Policy-AbC',
        documentNumber: 'Special-Document',
      ),
      database: db,
    );
    final glCount = await count('gl_entries');

    await expectLater(
      InsuranceFinancialService.postPolicy(
        command(
          operationId: 'NORMALIZED-KEY-2',
          policyNumber: '  policy-abc  ',
          documentNumber: 'Different-Document',
        ),
        database: db,
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      InsuranceFinancialService.postPolicy(
        command(
          operationId: 'NORMALIZED-KEY-3',
          policyNumber: 'Different-Policy',
          documentNumber: '  special-document  ',
        ),
        database: db,
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await count('insurance_policies'), 1);
    expect(await count('gl_entries'), glCount);
  });

  test('failed compatibility is transactional and does not record its marker',
      () async {
    final first = await InsuranceFinancialService.postPolicy(
      command(
        operationId: 'TRANSACTIONAL-COMPAT-1',
        policyNumber: 'TRANSACTIONAL-POLICY-1',
      ),
      database: db,
    );
    final second = await InsuranceFinancialService.postPolicy(
      command(
        operationId: 'TRANSACTIONAL-COMPAT-2',
        policyNumber: 'TRANSACTIONAL-POLICY-2',
      ),
      database: db,
    );
    expect(first.documentNumber, 'POL-0001');
    expect(second.documentNumber, 'POL-0002');

    await db!.execute('DROP INDEX uq_insurance_document_number');
    await db!.update(
      'insurance_policies',
      {'document_number': '  pol-0001  '},
      where: 'id=?',
      whereArgs: [second.policyId],
    );
    await db!.update(
      'document_sequences',
      {'next_value': 1},
      where: 'document_type=?',
      whereArgs: const ['INSURANCE_POLICY'],
    );
    await db!.delete(
      'schema_feature_migrations',
      where: 'feature_key=?',
      whereArgs: const [_phase10FeatureKey],
    );

    await endSession();
    DatabaseMigration.useDatabaseForTesting(null);
    await db!.close();
    db = null;

    await expectLater(
      DatabaseMigration.initDatabase(pathOverride: path),
      throwsA(isA<StateError>()),
    );

    db = await databaseFactoryFfi.openDatabase(path);
    expect(
      await db!.query(
        'schema_feature_migrations',
        where: 'feature_key=?',
        whereArgs: const [_phase10FeatureKey],
      ),
      isEmpty,
    );
    expect(await nextPolicyDocumentValue(), 1);
    expect(
      (await db!.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
  });
}
