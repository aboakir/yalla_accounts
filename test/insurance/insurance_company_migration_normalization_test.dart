import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/insurance_commercial_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp(
      'insurance_company_normalization_',
    );
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/normalization.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> insertLegacyPolicy(
    DatabaseExecutor executor, {
    required String id,
    required String companyName,
    String? insuranceCompanyId,
    String? insurerPartyId,
    int? insurerSupplierId,
  }) async {
    final now = DateTime.utc(2026, 9, 22).toIso8601String();
    await executor.insert('insurance_policies', {
      'id': id,
      'created_at': now,
      'updated_at': now,
      'vehicle_plate': 'LEGACY-$id',
      'vehicle_make': 'Legacy',
      'vehicle_model_year': '2020',
      'engine_cc': '1600',
      'insured_name': 'Legacy Insured',
      'insured_phone': '0599000000',
      'company_name': companyName,
      'start_date': '2026-09-22',
      'end_date': '2027-09-21',
      'payment_type': 'INSTALLMENT',
      'insurance_company_id': insuranceCompanyId,
      'insurer_party_id': insurerPartyId,
      'insurer_supplier_id': insurerSupplierId,
    });
  }

  test('legacy free-text company receives a generated INTEGER company id',
      () async {
    const companyName = 'Legacy Free Text Insurance';

    await LicenseRuntimeTables.runTrustedMigrationBackfill(db, () async {
      await db.transaction((txn) async {
        await insertLegacyPolicy(
          txn,
          id: 'legacy-free-text-policy',
          companyName: companyName,
        );
        await InsuranceCommercialTables.backfillLegacyCompanyParties(txn);
      });
    });

    final company = (await db.query(
      'insurance_companies',
      where: 'name=?',
      whereArgs: const [companyName],
    ))
        .single;
    expect(company['id'], isA<int>());
    expect(
      (await db.rawQuery(
        'SELECT typeof(id) storage_type FROM insurance_companies WHERE id=?',
        [company['id']],
      ))
          .single['storage_type'],
      'integer',
    );

    final companyId = (company['id'] as num).toInt();
    final partyId = company['party_id'].toString();
    final supplierId = (company['supplier_id'] as num).toInt();
    expect(
      await db.query(
        'party_roles',
        where: 'party_id=? AND role=? AND legacy_id=?',
        whereArgs: [partyId, 'SUPPLIER', supplierId.toString()],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'party_roles',
        where: 'party_id=? AND role=? AND legacy_id=?',
        whereArgs: [partyId, 'INSURANCE_COMPANY', companyId.toString()],
      ),
      hasLength(1),
    );

    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: const ['legacy-free-text-policy'],
    ))
        .single;
    expect(policy['insurance_company_id'].toString(), companyId.toString());
    expect(policy['insurer_party_id'], partyId);
    expect(policy['insurer_supplier_id'], supplierId);

    await LicenseRuntimeTables.runTrustedMigrationBackfill(
      db,
      () => db.transaction(
        InsuranceCommercialTables.backfillLegacyCompanyParties,
      ),
    );
    expect(
      (await db.rawQuery(
        'SELECT COUNT(*) count FROM insurance_companies WHERE name=?',
        [companyName],
      ))
          .single['count'],
      1,
    );
    expect(
      (await db.rawQuery(
        "SELECT COUNT(*) count FROM party_roles WHERE role='INSURANCE_COMPANY' "
        'AND legacy_id=?',
        [companyId.toString()],
      ))
          .single['count'],
      1,
    );
  });

  test('misaligned company role moves to the canonical Supplier Party',
      () async {
    const companyName = 'Misaligned Legacy Insurance';
    const stalePartyId = 'LEGACY:INSURANCE-COMPANY:77';
    late int supplierId;
    late int companyId;
    late String canonicalPartyId;

    await LicenseRuntimeTables.runTrustedMigrationBackfill(db, () async {
      await db.transaction((txn) async {
        supplierId = await txn.insert('suppliers', {'name': companyName});
        canonicalPartyId = (await txn.query(
          'party_roles',
          columns: const ['party_id'],
          where: 'role=? AND legacy_id=?',
          whereArgs: ['SUPPLIER', supplierId.toString()],
          limit: 1,
        ))
            .single['party_id']
            .toString();

        final now = DateTime.utc(2026, 9, 22).toIso8601String();
        await txn.insert('parties', {
          'id': stalePartyId,
          'display_name': companyName,
          'role_codes': '["INSURANCE_COMPANY"]',
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        companyId = await txn.insert('insurance_companies', {
          'party_id': stalePartyId,
          'supplier_id': supplierId,
          'code': 'MISALIGNED-77',
          'name': companyName,
          'default_commission_rate': 0.0,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        await txn.insert('party_roles', {
          'party_id': stalePartyId,
          'role': 'INSURANCE_COMPANY',
          'legacy_id': companyId.toString(),
          'created_at': now,
        });
        await insertLegacyPolicy(
          txn,
          id: 'misaligned-company-policy',
          companyName: companyName,
          insuranceCompanyId: companyId.toString(),
          insurerPartyId: stalePartyId,
          insurerSupplierId: supplierId,
        );

        await InsuranceCommercialTables.backfillLegacyCompanyParties(txn);
      });
    });

    final company = (await db.query(
      'insurance_companies',
      where: 'id=?',
      whereArgs: [companyId],
    ))
        .single;
    expect(company['party_id'], canonicalPartyId);
    expect(company['supplier_id'], supplierId);
    expect(
      await db.query(
        'party_roles',
        where: 'party_id=? AND role=? AND legacy_id=?',
        whereArgs: [
          canonicalPartyId,
          'INSURANCE_COMPANY',
          companyId.toString(),
        ],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'party_roles',
        where: 'party_id=? AND role=?',
        whereArgs: [stalePartyId, 'INSURANCE_COMPANY'],
      ),
      isEmpty,
    );

    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: const ['misaligned-company-policy'],
    ))
        .single;
    expect(policy['insurer_party_id'], canonicalPartyId);
    expect(policy['insurer_supplier_id'], supplierId);

    await LicenseRuntimeTables.runTrustedMigrationBackfill(
      db,
      () => db.transaction(
        InsuranceCommercialTables.backfillLegacyCompanyParties,
      ),
    );
    expect(
      (await db.rawQuery(
        'SELECT COUNT(*) count FROM insurance_companies WHERE id=?',
        [companyId],
      ))
          .single['count'],
      1,
    );
    expect(
      (await db.rawQuery(
        "SELECT COUNT(*) count FROM party_roles WHERE role='INSURANCE_COMPANY' "
        'AND legacy_id=?',
        [companyId.toString()],
      ))
          .single['count'],
      1,
    );
  });
}
