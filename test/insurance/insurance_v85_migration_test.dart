import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

const _bundledFixture = 'test/fixtures/migration/insurance84.db.gz';
const _bundledCompressedSha256 =
    'd3e371d9648c39ccae371ab3252b5adb1f94e6a9f29b35a3aacb05ce549ed4db';
const _bundledRawSha256 =
    '79efedd3328a076a78b25e662ed37889e174d3c411e8bb53bf487e8eadd39816';

int _count(List<Map<String, Object?>> rows) =>
    (rows.single['n'] as num).toInt();

Future<List<Map<String, Object?>>> _orderedRows(
  Database db,
  String table,
) async {
  return db.query(table, orderBy: 'id');
}

Future<void> _expectBalancedGl(Database db) async {
  final unbalanced = await db.rawQuery('''
    SELECT e.id,
           ROUND(COALESCE(SUM(l.debit),0),2) AS debit_total,
           ROUND(COALESCE(SUM(l.credit),0),2) AS credit_total
    FROM gl_entries e
    LEFT JOIN gl_lines l ON l.entry_id=e.id
    GROUP BY e.id
    HAVING ABS(COALESCE(SUM(l.debit),0)-COALESCE(SUM(l.credit),0)) > 0.005
  ''');
  expect(unbalanced, isEmpty, reason: 'Every migrated GL entry must balance');
}

Future<void> _runBundledSyntheticGate() async {
  final source = File(_bundledFixture);
  expect(await source.exists(), isTrue);
  final compressedBytes = await source.readAsBytes();
  expect(sha256.convert(compressedBytes).toString(), _bundledCompressedSha256);
  final sourceBytes = gzip.decode(compressedBytes);
  expect(sha256.convert(sourceBytes).toString(), _bundledRawSha256);
  expect(
    sourceBytes.sublist(18, 20),
    [1, 1],
    reason: 'The source fixture must not depend on WAL sidecars',
  );

  final temp = await Directory.systemTemp.createTemp('insurance_v84_upgrade_');
  final working = '${temp.path}/upgrade.db';
  await File(working).writeAsBytes(sourceBytes, flush: true);

  Database? beforeDb;
  Database? db;
  try {
    beforeDb = await databaseFactoryFfi.openDatabase(
      working,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    expect(await beforeDb.getVersion(), 84);
    expect(
      (await beforeDb.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
    expect(await beforeDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);

    final financialBefore = <String, List<Map<String, Object?>>>{};
    for (final table in const [
      'gl_entries',
      'gl_lines',
      'payments',
      'cheques',
    ]) {
      financialBefore[table] = await _orderedRows(beforeDb, table);
    }
    final countsBefore = <String, int>{};
    for (final table in const [
      'clients',
      'insurance_companies',
      'insurance_policies',
      'insurance_policy_installments',
      'gl_entries',
      'gl_lines',
      'payments',
      'cheques',
    ]) {
      countsBefore[table] = _count(await beforeDb.rawQuery(
        'SELECT COUNT(*) n FROM $table',
      ));
    }
    expect(
      _count(await beforeDb.rawQuery(
        'SELECT COUNT(*) n FROM insurance_companies WHERE id=8401',
      )),
      1,
    );
    expect(countsBefore['insurance_policies'], 1);
    expect(countsBefore['insurance_policy_installments'], 1);
    await _expectBalancedGl(beforeDb);
    await beforeDb.close();
    beforeDb = null;

    db = await DatabaseMigration.initDatabase(pathOverride: working);
    expect(await db.getVersion(), 85);
    expect(
      (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

    for (final entry in countsBefore.entries) {
      final after = _count(await db.rawQuery(
        'SELECT COUNT(*) n FROM ${entry.key}',
      ));
      expect(after, entry.value, reason: '${entry.key} row count changed');
    }
    for (final entry in financialBefore.entries) {
      expect(
        await _orderedRows(db, entry.key),
        entry.value,
        reason: '${entry.key} financial facts changed',
      );
    }
    await _expectBalancedGl(db);

    final policyColumns = (await db.rawQuery(
      'PRAGMA table_info(insurance_policies)',
    ))
        .map((row) => row['name'])
        .toSet();
    expect(
      policyColumns,
      containsAll(const [
        'operation_id',
        'document_number',
        'policy_number',
        'engine_number',
        'chassis_number',
        'posting_request_json',
        'insured_party_id',
        'insurer_party_id',
        'insurer_supplier_id',
        'product_id',
        'gl_entry_id',
        'posting_status',
      ]),
    );

    final policy = (await db.query(
      'insurance_policies',
      where: 'id=?',
      whereArgs: const ['synthetic-v84-policy'],
    ))
        .single;
    expect(policy['vehicle_plate'], 'V84-TEST');
    expect(policy['insurance_company_id'].toString(), '8401');
    expect(policy['insurer_party_id'], isNotNull);
    expect(policy['insurer_supplier_id'], isNotNull);
    expect(policy['posting_status'], 'DRAFT');
    expect(policy['gl_entry_id'], isNull);
    expect(
      policy['document_number'],
      isNull,
      reason: 'Migration must not invent a posted document for a v84 draft',
    );

    final company = (await db.query(
      'insurance_companies',
      where: 'id=?',
      whereArgs: const [8401],
    ))
        .single;
    expect(company['party_id'], policy['insurer_party_id']);
    expect(company['supplier_id'], policy['insurer_supplier_id']);
    expect((company['code'] ?? '').toString(), startsWith('INS-'));
    expect(
      _count(await db.rawQuery(
        "SELECT COUNT(*) n FROM party_roles "
        "WHERE role='INSURANCE_COMPANY' AND legacy_id='8401' "
        'AND party_id=?',
        [company['party_id']],
      )),
      1,
    );
    expect(
      _count(await db.rawQuery(
        'SELECT COUNT(*) n FROM suppliers WHERE id=?',
        [company['supplier_id']],
      )),
      1,
    );

    final installment = (await db.query(
      'insurance_policy_installments',
      where: 'id=?',
      whereArgs: const ['synthetic-v84-installment'],
    ))
        .single;
    expect(installment['amount'], 1000.0);
    expect(installment['due_date'], '2026-10-22');
    expect(
      _count(await db.rawQuery(
        'SELECT COUNT(*) n FROM insurance_policy_payments',
      )),
      0,
      reason:
          'A scheduled installment must not become a receipt during migration',
    );

    final sequence = (await db.query(
      'document_sequences',
      where: 'document_type=?',
      whereArgs: const ['INSURANCE_POLICY'],
    ))
        .single;
    expect(sequence['prefix'], 'POL');
    expect((sequence['next_value'] as num).toInt(), greaterThanOrEqualTo(1));
    expect(
      _count(await db.rawQuery(
        "SELECT COUNT(*) n FROM schema_feature_migrations "
        "WHERE feature_key='insurance_phase10_financial_bridge_v85' "
        'AND from_schema_version=84',
      )),
      1,
    );

    final stableCounts = <String, int>{
      for (final table in const [
        'suppliers',
        'parties',
        'party_roles',
        'insurance_companies',
        'insurance_policies',
        'gl_entries',
        'gl_lines',
      ])
        table: _count(await db.rawQuery('SELECT COUNT(*) n FROM $table')),
    };
    await db.close();
    db = null;
    DatabaseMigration.useDatabaseForTesting(null);
    db = await DatabaseMigration.initDatabase(pathOverride: working);
    for (final entry in stableCounts.entries) {
      expect(
        _count(await db.rawQuery('SELECT COUNT(*) n FROM ${entry.key}')),
        entry.value,
        reason: '${entry.key} changed on same-v85 reopen',
      );
    }
    await _expectBalancedGl(db);

    expect(
      await source.readAsBytes(),
      compressedBytes,
      reason: 'The source fixture itself must remain byte-for-byte unchanged',
    );
  } finally {
    DatabaseMigration.useDatabaseForTesting(null);
    if (beforeDb != null && beforeDb.isOpen) await beforeDb.close();
    if (db != null && db.isOpen) await db.close();
    await temp.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    DatabaseMigration.useDatabaseForTesting(null);
  });

  test(
    'bundled synthetic historical-lineage v84 migrates on a copy to v85',
    _runBundledSyntheticGate,
  );
}
