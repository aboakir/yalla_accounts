import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_reconciliation_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cheque_reconcile_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    session = await startAccountingSession(db, 'cheque-reconcile-owner');
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    await session.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('PHASE21 recovers evidenced legacy cheque exactly once with audit',
      () async {
    final supplierId =
        await db.insert('suppliers', {'name': 'Legacy Cheque Supplier'});
    final apId = await db.insert('accounts', {
      'code': '2200.S$supplierId',
      'name': 'Legacy Supplier AP',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT',
    });
    final incomingId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1020'],
      limit: 1,
    ))
        .single['id'] as int;
    final outgoingId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1030'],
      limit: 1,
    ))
        .single['id'] as int;

    const voucherId = 'LEGACY-PV-CHEQUE';
    final date = DateTime(2025, 12, 23);
    final glId = await AccountingTables.postEntryGLOn(
      ex: db,
      date: date,
      source: 'VOUCHER',
      sourceId: voucherId,
      note: 'legacy cheque voucher',
      lines: [
        {
          'account_id': apId,
          'debit': 2000.0,
          'credit': 0.0,
          'party_type': 'SUPPLIER',
          'party_id': supplierId.toString(),
        },
        {
          'account_id': incomingId,
          'debit': 0.0,
          'credit': 2000.0,
        },
      ],
    );

    await db.insert('vouchers', {
      'id': voucherId,
      'voucher_type': 'PAYMENT',
      'voucher_number': 'P-LEGACY',
      'party_type': 'SUPPLIER',
      'party_id': supplierId.toString(),
      'amount': 2000.0,
      'currency': 'ILS',
      'date': date.toIso8601String(),
      'method': 'cheque',
      'gl_entry_id': glId,
      'is_posted': 0,
      'status': 'DRAFT',
      'created_at': date.toIso8601String(),
      'updated_at': date.toIso8601String(),
    });

    final before = await ChequeReconciliationService.audit(db);
    expect(
      before.issues.map((e) => e.code),
      contains('VOUCHER_CHEQUE_WITHOUT_INSTRUMENT'),
    );
    expect(
      before.issues.map((e) => e.code),
      contains('CHEQUE_VOUCHER_POSTING_METADATA_STALE'),
    );
    expect(before.repairableCount, 1);

    final backup = '${temp.path}/before.db';
    await File('${temp.path}/test.db').copy(backup);
    final result = await ChequeReconciliationService.reconcileSafe(
      db,
      backupPath: backup,
    );
    expect(result.repairedRecords, 1);
    expect(result.createdChequeIds, hasLength(1));
    expect(result.after.financialMismatchCount, 0);
    expect(
      result.after.issues.map((e) => e.code),
      contains('LEGACY_CHEQUE_METADATA_INCOMPLETE'),
    );

    final chequeId = result.createdChequeIds.single;
    final cheque = (await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
    ))
        .single;
    expect(cheque['direction'], 'ISSUED');
    expect(cheque['status'], 'issued');
    expect(cheque['amount'], 2000.0);
    expect(cheque['is_legacy_incomplete'], 1);
    expect(cheque['cheque_no'], '');
    expect(cheque['bank_name'], '');
    expect(cheque['due_date'], isNull);
    expect(cheque['recipient_name'], 'Legacy Cheque Supplier');
    expect(cheque['gl_entry_id'], glId);

    expect(
      await db.query(
        'cheque_voucher_links',
        where: 'cheque_id=?',
        whereArgs: [chequeId],
      ),
      hasLength(1),
    );
    final allocations = await db.query(
      'cheque_allocations',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
    );
    expect(allocations, hasLength(1));
    expect(allocations.single['allocation_type'], 'PARTY_ACCOUNT');
    expect(allocations.single['target_id'], supplierId.toString());

    final originalLines = await db.query(
      'gl_lines',
      where: 'entry_id=?',
      whereArgs: [glId],
    );
    expect(originalLines.every((r) => r['cheque_id'] == null), isTrue);
    expect(cheque['gl_entry_id'], glId);

    final reclass = await db.query(
      'gl_entries',
      where: 'source=?',
      whereArgs: ['CHEQUE_RECONCILIATION'],
    );
    expect(reclass, hasLength(1));
    final reclassId = reclass.single['id'] as int;
    final reclassLines = await db.query(
      'gl_lines',
      where: 'entry_id=?',
      whereArgs: [reclassId],
    );
    expect(
      reclassLines.fold<double>(
        0,
        (s, r) => s + (r['debit'] as num).toDouble(),
      ),
      2000,
    );
    expect(
      reclassLines.fold<double>(
        0,
        (s, r) => s + (r['credit'] as num).toDouble(),
      ),
      2000,
    );

    Future<double> net(int accountId) async {
      final row = (await db.rawQuery(
        'SELECT COALESCE(SUM(debit-credit),0) n FROM gl_lines WHERE account_id=?',
        [accountId],
      ))
          .single;
      return (row['n'] as num).toDouble();
    }

    expect(await net(incomingId), 0);
    expect(await net(outgoingId), -2000);

    final voucher = (await db.query(
      'vouchers',
      where: 'id=?',
      whereArgs: [voucherId],
    ))
        .single;
    expect(voucher['cheque_id'], isNull);
    expect(voucher['is_posted'], 0);
    expect(voucher['status'], 'DRAFT');

    final audit = await db.query(
      'app_audit_events',
      where: 'action=?',
      whereArgs: ['CHEQUE_LEGACY_INSTRUMENT_RECOVERED'],
    );
    expect(audit, hasLength(1));
    final auditMetadata = jsonDecode(
      audit.single['metadata_json'].toString(),
    ) as Map<String, dynamic>;
    expect(auditMetadata['backup_path'], backup);

    final retry = await ChequeReconciliationService.reconcileSafe(
      db,
      backupPath: backup,
    );
    expect(retry.repairedRecords, 0);
    expect(await db.query('cheques'), hasLength(1));
    expect(
      await db.query(
        'gl_entries',
        where: 'source=?',
        whereArgs: ['CHEQUE_RECONCILIATION'],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'app_audit_events',
        where: 'action=?',
        whereArgs: ['CHEQUE_LEGACY_INSTRUMENT_RECOVERED'],
      ),
      hasLength(1),
    );
  });
}
