import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_integrity_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_inbound_router.dart';

const deviceA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const deviceB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const installA = 'aaaaaaaa-1111-4aaa-8aaa-aaaaaaaaaaaa';
const installB = 'bbbbbbbb-2222-4bbb-8bbb-bbbbbbbbbbbb';

class _MemorySyncServer implements SyncV3Transport {
  final List<SyncV3PullChange> _changes = <SyncV3PullChange>[];
  final Map<String, int> _sequences = <String, int>{};
  int _sequence = 0;

  @override
  bool get isConfigured => true;
  int get acceptedChanges => _changes.length;

  @override
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows) async {
    final results = <SyncV3PushResult>[];
    for (final row in rows) {
      final changeId = row['change_id']!.toString();
      final existing = _sequences[changeId];
      final sequence = existing ?? ++_sequence;
      if (existing == null) {
        _sequences[changeId] = sequence;
        _changes.add(SyncV3PullChange(
          serverSequence: sequence,
          changeId: changeId,
          organizationId: row['organization_id']!.toString(),
          entityType: row['entity_type']!.toString(),
          entityId: row['entity_id']!.toString(),
          entityUuid: row['entity_uuid']!.toString(),
          operation: row['operation']!.toString(),
          revision: (row['revision'] as num).toInt(),
          occurredAt: DateTime.parse(row['occurred_at']!.toString()),
          payload: Map<String, Object?>.from(
            jsonDecode(row['payload_json']!.toString()) as Map,
          ),
        ));
      }
      results.add(SyncV3PushResult(
        changeId: changeId,
        idempotencyKey: row['idempotency_key']!.toString(),
        disposition: 'ACKNOWLEDGED',
        serverSequence: sequence,
      ));
    }
    return SyncV3PushResponse(results);
  }

  @override
  Future<SyncV3PullResponse> pull({
    required int afterServerSequence,
    int limit = 200,
  }) async {
    final available = _changes
        .where((change) => change.serverSequence > afterServerSequence)
        .take(limit)
        .toList(growable: false);
    final next =
        available.isEmpty ? afterServerSequence : available.last.serverSequence;
    return SyncV3PullResponse(
      fromSequence: afterServerSequence,
      nextSequence: next,
      hasMore: _changes.any((change) => change.serverSequence > next),
      changes: available,
    );
  }
}

Future<String> _organization(Database db) async {
  final rows = await db.query(
    'organization_identity',
    columns: const <String>['organization_id'],
    where: 'singleton_id=1',
    limit: 1,
  );
  return rows.single['organization_id']!.toString();
}

Future<void> _alignOrganization(Database db, String organizationId) async {
  final current = await _organization(db);
  if (current == organizationId) return;
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'organizations',
    <String, Object?>{
      'id': organizationId,
      'display_name': 'Phase20 shared organization',
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    },
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  await db.update(
    'organization_identity',
    <String, Object?>{'organization_id': organizationId},
    where: 'singleton_id=1',
  );
  for (final table in const <String>['users', 'workshop_settings']) {
    final exists = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      <Object?>[table],
    );
    if (exists.isNotEmpty) {
      await db.update(
        table,
        <String, Object?>{'organization_id': organizationId},
        where: 'organization_id=?',
        whereArgs: <Object?>[current],
      );
    }
  }
}

Future<void> _setWritable(Database db, String organizationId) async {
  final now = DateTime.now().toUtc();
  await db.update(
    LicenseRuntimeTables.table,
    <String, Object?>{
      'mode': LicenseRuntimeMode.writable,
      'reason': 'Phase20 isolated multi-device acceptance fixture',
      'organization_id': organizationId,
      'subscription_id': '11111111-2222-4333-8444-555555555555',
      'license_id': '66666666-7777-4888-8999-aaaaaaaaaaaa',
      'effective_at': now.toIso8601String(),
      'license_expires_at': now.add(const Duration(days: 30)).toIso8601String(),
      'source': 'SIGNED_LICENSE',
      'last_verified_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    },
    where: 'singleton_id=1',
  );
}

Future<void> _installDevice(
  Database db, {
  required String organizationId,
  required String installationId,
  required String deviceId,
  required String marker,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('installation_identity', <String, Object?>{
    'singleton_id': 1,
    'organization_id': organizationId,
    'installation_id': installationId,
    'device_id': deviceId,
    'key_algorithm': 'ED25519',
    'public_key_b64url': 'test-$marker',
    'public_key_sha256': marker * 64,
    'fingerprint_sha256': marker * 64,
    'platform': 'windows',
    'platform_version': 'phase20-isolated',
    'app_version': '1.0.0+20',
    'identity_generation': 1,
    'binding_state': 'BOUND',
    'bound_at': now,
    'created_at': now,
    'updated_at': now,
  });
}

Future<Map<String, Object?>> _employeeFixture(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(employees)');
  final result = <String, Object?>{};
  for (final column in info) {
    if (column['notnull'] == 1 && column['dflt_value'] == null) {
      final type = column['type'].toString().toUpperCase();
      result[column['name'] as String] = type.contains('TEXT') ? '' : 0;
    }
  }
  result.addAll(<String, Object?>{
    'id': 'phase20-employee',
    'full_name': 'Phase20 Employee',
    'employee_code': 'P20',
    'job_title': 'Painter',
    'hire_date': '2026-01-01',
    'phone': '000',
    'email': 'phase20@example.test',
    'address': 'test',
    'status': 'active',
    'base_salary': 1000.0,
    'allowances': 0.0,
    'deductions': 0.0,
    'advances': 0.0,
    'total_work_days': 0,
    'total_hours': 0.0,
    'absences': 0,
    'late_days': 0,
    'notes': '',
    'created_at': '2026-09-18T00:00:00.000Z',
    'payment_method': 'cash',
    'work_days_per_week': 6,
    'hours_per_day': 8,
  });
  return result;
}

Future<int> _account(
  Database db,
  String code, {
  required String name,
  required String type,
  required String normal,
}) async {
  final rows = await db.query(
    'accounts',
    columns: const <String>['id'],
    where: 'code=?',
    whereArgs: <Object?>[code],
  );
  if (rows.isNotEmpty) return (rows.single['id'] as num).toInt();
  return db.insert('accounts', <String, Object?>{
    'code': code,
    'name': name,
    'type': type,
    'normal_balance': normal,
    'is_postable': 1,
    'is_system': 0,
    'is_active': 1,
    'is_legacy': 0,
  });
}

Future<int> _insertGl(
  Transaction txn, {
  required String source,
  required String sourceId,
  required int debitAccount,
  required int creditAccount,
  required double amount,
  String? employeeId,
}) async {
  final now = DateTime.utc(2026, 9, 18, 6).toIso8601String();
  final entry = await txn.insert('gl_entries', <String, Object?>{
    'date': now,
    'source': source,
    'source_id': sourceId,
    'posting_version': 1,
    'note': 'Phase20 $source',
    'created_at': now,
  });
  await txn.insert('gl_lines', <String, Object?>{
    'entry_id': entry,
    'account_id': debitAccount,
    'debit': amount,
    'credit': 0.0,
    'party_type': employeeId == null ? null : 'EMPLOYEE',
    'party_id': employeeId,
    'created_at': now,
  });
  await txn.insert('gl_lines', <String, Object?>{
    'entry_id': entry,
    'account_id': creditAccount,
    'debit': 0.0,
    'credit': amount,
    'party_type': employeeId == null ? null : 'EMPLOYEE',
    'party_id': employeeId,
    'created_at': now,
  });
  await AccountingIntegrityTables.recordPostingEvent(
    txn,
    glEntryId: entry,
    source: source,
    sourceId: sourceId,
    canonicalSource: source,
    reversalOf: null,
    actorUserId: null,
  );
  return entry;
}

Future<int> _count(
  Database db,
  String sql, [
  List<Object?> args = const <Object?>[],
]) async {
  final rows = await db.rawQuery(sql, args);
  return (rows.single.values.first as num).toInt();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('Phase20 A to server to B preserves payroll and posted GL truth',
      () async {
    final root = await Directory.systemTemp.createTemp('phase20_fin_sync_');
    final dbA = await DatabaseMigration.initDatabase(
      pathOverride: '${root.path}/a.db',
    );
    final dbB = await DatabaseMigration.initDatabase(
      pathOverride: '${root.path}/b.db',
    );
    final orgA = await _organization(dbA);
    await _alignOrganization(dbB, orgA);
    await _setWritable(dbA, orgA);
    await _setWritable(dbB, orgA);
    await _installDevice(
      dbA,
      organizationId: orgA,
      installationId: installA,
      deviceId: deviceA,
      marker: 'a',
    );
    await _installDevice(
      dbB,
      organizationId: orgA,
      installationId: installB,
      deviceId: deviceB,
      marker: 'b',
    );
    final server = _MemorySyncServer();
    final coordinatorA = UnifiedSyncCoordinatorV3(status: SyncStateService());
    final coordinatorB = UnifiedSyncCoordinatorV3(status: SyncStateService());
    coordinatorA.configureTransport(server);
    coordinatorB.configureTransport(server);
    coordinatorB.configureInboundApplier(UnifiedSyncInboundRouter.apply);

    try {
      final salaryExpense = await _account(
        dbA,
        '5100',
        name: 'Salary Expense',
        type: 'EXPENSE',
        normal: 'DEBIT',
      );
      final cash = await _account(
        dbA,
        '1000',
        name: 'Cash',
        type: 'ASSET',
        normal: 'DEBIT',
      );
      final payrollPayable = await _account(
        dbA,
        '2140.Ephase20-employee',
        name: 'Payroll Payable - Phase20',
        type: 'LIABILITY',
        normal: 'CREDIT',
      );
      final employeeFixture = await _employeeFixture(dbA);
      await dbA.transaction((txn) async {
        await txn.insert('employees', employeeFixture);
        await txn.insert('payroll_runs', <String, Object?>{
          'id': 'phase20-run',
          'employee_id': 'phase20-employee',
          'gross': 1000.0,
          'allowances': 0.0,
          'deductions': 0.0,
          'advance_applied': 0.0,
          'net': 1000.0,
          'amount_paid': 0.0,
          'status': 'ACCRUED',
          'period_start': '2026-09-01T00:00:00.000Z',
          'period_end': '2026-09-30T23:59:59.000Z',
          'accrual_date': '2026-09-30T00:00:00.000Z',
          'method': 'cash',
          'note': 'Phase20 payroll',
          'created_at': '2026-09-18T06:00:00.000Z',
        });
        await _insertGl(
          txn,
          source: 'PAYROLL_ACCRUAL',
          sourceId: 'phase20-run',
          debitAccount: salaryExpense,
          creditAccount: payrollPayable,
          amount: 1000,
          employeeId: 'phase20-employee',
        );
        await txn.insert('vouchers', <String, Object?>{
          'id': 'phase20-voucher',
          'voucher_type': 'PAYMENT',
          'voucher_number': 'PV-P20',
          'party_type': 'EMPLOYEE',
          'party_id': 'phase20-employee',
          'amount': 100.0,
          'currency': 'ILS',
          'date': '2026-09-18T06:10:00.000Z',
          'method': 'CASH',
          'source': 'PAYROLL_ENTITLEMENT',
          'source_id': 'phase20-run',
          'is_posted': 0,
          'status': 'DRAFT',
          'created_at': '2026-09-18T06:10:00.000Z',
          'updated_at': '2026-09-18T06:10:00.000Z',
        });
        final paymentGl = await _insertGl(
          txn,
          source: 'VOUCHER',
          sourceId: 'phase20-voucher',
          debitAccount: payrollPayable,
          creditAccount: cash,
          amount: 100,
          employeeId: 'phase20-employee',
        );
        await txn.update(
          'vouchers',
          <String, Object?>{
            'gl_entry_id': paymentGl,
            'is_posted': 1,
            'status': 'POSTED',
            'posted_at': '2026-09-18T06:10:00.000Z',
            'updated_at': '2026-09-18T06:10:00.000Z',
          },
          where: 'id=?',
          whereArgs: <Object?>['phase20-voucher'],
        );
        await txn.insert('payroll_payments', <String, Object?>{
          'id': 'phase20-pay',
          'run_id': 'phase20-run',
          'amount': 100.0,
          'date': '2026-09-18T06:10:00.000Z',
          'method': 'cash',
          'note': 'Phase20 payment',
          'voucher_id': 'phase20-voucher',
        });
        await txn.update(
          'payroll_runs',
          <String, Object?>{'amount_paid': 100.0, 'status': 'ACCRUED'},
          where: 'id=?',
          whereArgs: <Object?>['phase20-run'],
        );
      });
      final rawGlLine = (await dbA.query(
        'sync_outbox',
        columns: const <String>['payload_json'],
        where: "entity_type='gl_line' AND state='PENDING'",
        orderBy: 'created_at ASC',
        limit: 1,
      ))
          .single['payload_json']
          .toString();
      expect(rawGlLine, isNot(contains('"account_id"')));
      expect(rawGlLine, isNot(contains('"entry_id"')));
      expect(rawGlLine, contains('"account_code"'));
      expect(rawGlLine, contains('"gl_entry_entity_uuid"'));

      final rawVoucher = (await dbA.query(
        'sync_outbox',
        columns: const <String>['payload_json'],
        where: "entity_type='voucher' AND state='PENDING'",
        orderBy: 'created_at ASC',
        limit: 1,
      ))
          .single['payload_json']
          .toString();
      expect(rawVoucher, isNot(contains('"party_id"')));
      expect(rawVoucher, contains('"party_entity_uuid"'));
      final pushed = await coordinatorA.cycle(database: dbA);
      expect(pushed.rejected, 0);
      expect(pushed.conflicts, 0);
      expect(pushed.acknowledged, greaterThanOrEqualTo(10));
      expect(server.acceptedChanges, pushed.acknowledged);

      final pulled = await coordinatorB.cycle(database: dbB);
      expect(pulled.rejected, 0);
      expect(pulled.conflicts, 0);
      expect(pulled.pulled, server.acceptedChanges);

      expect(
        await dbB.query(
          'employees',
          where: 'id=?',
          whereArgs: const <Object?>['phase20-employee'],
        ),
        hasLength(1),
      );
      expect(
        await dbB.query(
          'payroll_runs',
          where: 'id=?',
          whereArgs: const <Object?>['phase20-run'],
        ),
        hasLength(1),
      );
      expect(
        await dbB.query(
          'payroll_payments',
          where: 'id=?',
          whereArgs: const <Object?>['phase20-pay'],
        ),
        hasLength(1),
      );
      final voucherB = (await dbB.query(
        'vouchers',
        where: 'id=?',
        whereArgs: const <Object?>['phase20-voucher'],
      ))
          .single;
      expect(voucherB['status'], 'POSTED');
      expect(voucherB['gl_entry_id'], isNotNull);

      expect(
        await _count(
          dbB,
          "SELECT COUNT(*) FROM gl_entries WHERE source IN ('PAYROLL_ACCRUAL','VOUCHER')",
        ),
        2,
      );
      expect(
          await _count(dbB, 'SELECT COUNT(*) FROM accounting_audit_events'), 2);
      final unbalanced = await _count(dbB, '''
        SELECT COUNT(*) FROM (
          SELECT e.id,
            SUM(ROUND(l.debit*100)) AS d,
            SUM(ROUND(l.credit*100)) AS c,
            COUNT(l.id) AS n
          FROM gl_entries e
          JOIN gl_lines l ON l.entry_id=e.id
          WHERE e.source IN ('PAYROLL_ACCRUAL','VOUCHER')
          GROUP BY e.id
          HAVING n<2 OR d<=0 OR d<>c
        )
      ''');
      expect(unbalanced, 0);

      final outboundB = await _count(
        dbB,
        "SELECT COUNT(*) FROM sync_outbox WHERE state IN ('PENDING','SENDING')",
      );
      expect(outboundB, 0);

      final localEchoB = await _count(
        dbB,
        "SELECT COUNT(*) FROM sync_change_log WHERE origin='local'",
      );
      expect(localEchoB, 0);
      final beforeRetry = await _count(dbB, 'SELECT COUNT(*) FROM gl_entries');
      final retry = await coordinatorB.cycle(database: dbB);
      expect(retry.pulled, 0);
      expect(await _count(dbB, 'SELECT COUNT(*) FROM gl_entries'), beforeRetry);

      final regA = (await dbA.query(
        SyncFoundationTables.registry,
        where: "entity_type='payroll_run' AND local_id='phase20-run'",
      ))
          .single;
      final regB = (await dbB.query(
        SyncFoundationTables.registry,
        where: "entity_type='payroll_run' AND local_id='phase20-run'",
      ))
          .single;
      expect(regB['entity_uuid'], regA['entity_uuid']);
      expect(regB['revision'], regA['revision']);
    } finally {
      await coordinatorA.stop();
      await coordinatorB.stop();
      await dbA.close();
      await dbB.close();
      await root.delete(recursive: true);
      DatabaseMigration.useDatabaseForTesting(null);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
