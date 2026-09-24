import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_inbound_router.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

class MemoryServer implements SyncV3Transport {
  final changes = <SyncV3PullChange>[];
  final sequences = <String, int>{};
  int sequence = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows) async {
    final results = <SyncV3PushResult>[];
    for (final row in rows) {
      final changeId = row['change_id']!.toString();
      final existing = sequences[changeId];
      final seq = existing ?? ++sequence;
      if (existing == null) {
        sequences[changeId] = seq;
        changes.add(SyncV3PullChange(
          serverSequence: seq,
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
        serverSequence: seq,
      ));
    }
    return SyncV3PushResponse(results);
  }

  @override
  Future<SyncV3PullResponse> pull({
    required int afterServerSequence,
    int limit = 200,
  }) async {
    final available = changes
        .where((c) => c.serverSequence > afterServerSequence)
        .take(limit)
        .toList(growable: false);
    final next =
        available.isEmpty ? afterServerSequence : available.last.serverSequence;
    return SyncV3PullResponse(
      fromSequence: afterServerSequence,
      nextSequence: next,
      hasMore: changes.any((c) => c.serverSequence > next),
      changes: available,
    );
  }
}

Future<String> organization(Database db) async =>
    (await db.query('organization_identity',
            columns: const ['organization_id'],
            where: 'singleton_id=1',
            limit: 1))
        .single['organization_id']!
        .toString();

Future<void> alignOrganization(Database db, String target) async {
  final current = await organization(db);
  if (current == target) return;
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'organizations',
    {
      'id': target,
      'display_name': 'Phase54 Shared',
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    },
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  await db.update('organization_identity', {'organization_id': target},
      where: 'singleton_id=1');
  for (final table in ['users', 'workshop_settings']) {
    await db.update(table, {'organization_id': target},
        where: 'organization_id=?', whereArgs: [current]);
  }
}

Future<void> installDevice(
  Database db,
  String org,
  String installation,
  String device,
  String marker,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('installation_identity', {
    'singleton_id': 1,
    'organization_id': org,
    'installation_id': installation,
    'device_id': device,
    'key_algorithm': 'ED25519',
    'public_key_b64url': 'phase54-$marker',
    'public_key_sha256': marker * 64,
    'fingerprint_sha256': marker * 64,
    'platform': 'test',
    'platform_version': 'phase54',
    'app_version': '1.0.3+22',
    'identity_generation': 1,
    'binding_state': 'BOUND',
    'bound_at': now,
    'created_at': now,
    'updated_at': now,
  });
}

Future<Map<String, Object?>> partyByName(Database db, String name) async =>
    Map<String, Object?>.from((await db.query(
      'parties',
      where: 'display_name=?',
      whereArgs: [name],
    ))
        .single);

Future<int> clientForParty(Database db, String partyId) async {
  final row = (await db.query(
    'party_roles',
    columns: const ['legacy_id'],
    where: 'party_id=? AND role=?',
    whereArgs: [partyId, 'CUSTOMER'],
  ))
      .single;
  return int.parse(row['legacy_id']!.toString());
}

Future<int> pending(Database db) async => (await db.rawQuery(
      "SELECT COUNT(*) n FROM sync_outbox WHERE state IN ('PENDING','SENDING')",
    ))
        .single['n'] as int;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('phase54 receipts payments and cheque converge both directions',
      () async {
    final root = await Directory.systemTemp.createTemp('phase54_financial_');
    final dbA =
        await DatabaseMigration.initDatabase(pathOverride: '${root.path}/a.db');
    final dbB =
        await DatabaseMigration.initDatabase(pathOverride: '${root.path}/b.db');
    final org = await organization(dbA);
    await alignOrganization(dbB, org);
    await installDevice(
      dbA,
      org,
      'aaaaaaaa-1111-4aaa-8aaa-aaaaaaaaaaaa',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a',
    );
    await installDevice(
      dbB,
      org,
      'bbbbbbbb-2222-4bbb-8bbb-bbbbbbbbbbbb',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'b',
    );

    await dbB.insert('clients', {
      'name': 'Phase54 Dummy',
      'type': 'أفراد',
      'phone': '',
      'email': '',
      'address': '',
      'notes': '',
    });

    final server = MemoryServer();
    final a = UnifiedSyncCoordinatorV3(status: SyncStateService());
    final b = UnifiedSyncCoordinatorV3(status: SyncStateService());
    a.configureTransport(server);
    b.configureTransport(server);
    a.configureInboundApplier(UnifiedSyncInboundRouter.apply);
    b.configureInboundApplier(UnifiedSyncInboundRouter.apply);

    try {
      await PartyFinancialService.createParty(
        name: 'Phase54 Customer',
        phone: '0599005454',
        address: 'Bethlehem',
        customer: true,
        supplier: false,
        database: dbA,
      );
      expect((await a.cycle(database: dbA)).acknowledged, 1);
      expect((await b.cycle(database: dbB)).pulled, greaterThanOrEqualTo(1));

      final partyA = await partyByName(dbA, 'Phase54 Customer');
      final partyB = await partyByName(dbB, 'Phase54 Customer');
      final clientA = await clientForParty(dbA, partyA['id']!.toString());
      final clientB = await clientForParty(dbB, partyB['id']!.toString());
      expect(clientB, isNot(clientA));

      final now = DateTime.utc(2026, 9, 25, 8);
      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.insert('receipt_headers', {
          'receipt_number': 9101,
          'client_id': clientA,
          'date': now.toIso8601String(),
          'method': 'CHEQUE',
          'total_amount': 250.0,
          'allocated_amount': 0.0,
          'credit_amount': 250.0,
          'status': 'posted',
          'notes': 'PC receipt',
          'created_at': now.toIso8601String(),
        });
        await txn.insert('cheques', {
          'uuid': '54545454-5454-4454-8454-545454545454',
          'cheque_no': 'CH-5401',
          'cheque_type': 'incoming',
          'status': 'received',
          'drawer_name': 'Phase54 Customer',
          'bank_name': 'Test Bank',
          'amount': 250.0,
          'currency': 'ILS',
          'issue_date': now.toIso8601String(),
          'due_date': now.add(const Duration(days: 30)).toIso8601String(),
          'client_id': clientA,
          'direction': 'RECEIVED',
          'instrument_key': 'phase54-cheque-1',
          'is_legacy_incomplete': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      });

      final pushedA = await a.cycle(database: dbA);
      expect(pushedA.acknowledged, greaterThanOrEqualTo(2));
      final pulledB = await b.cycle(database: dbB);
      expect(pulledB.pulled, greaterThanOrEqualTo(2));

      final receiptB = (await dbB.query(
        'receipt_headers',
        where: 'receipt_number=?',
        whereArgs: [9101],
      ))
          .single;
      expect(receiptB['client_id'], clientB);
      expect(receiptB['total_amount'], 250.0);

      final chequeB = (await dbB.query(
        'cheques',
        where: 'cheque_no=?',
        whereArgs: ['CH-5401'],
      ))
          .single;
      expect(chequeB['client_id'], clientB);
      expect(chequeB['direction'], 'RECEIVED');
      expect(chequeB['amount'], 250.0);

      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
          'cheques',
          {
            'status': 'cleared',
            'cleared_at': now.add(const Duration(days: 2)).toIso8601String(),
            'updated_at': now.add(const Duration(days: 2)).toIso8601String(),
          },
          where: 'cheque_no=?',
          whereArgs: ['CH-5401'],
        );
      });
      expect(
          (await a.cycle(database: dbA)).acknowledged, greaterThanOrEqualTo(1));
      expect((await b.cycle(database: dbB)).pulled, greaterThanOrEqualTo(1));
      expect(
        (await dbB
                .query('cheques', where: 'cheque_no=?', whereArgs: ['CH-5401']))
            .single['status'],
        'cleared',
      );

      await SyncFoundationService.transaction(dbB, (txn) async {
        await txn.insert('receipt_headers', {
          'receipt_number': 9102,
          'client_id': clientB,
          'date': now.add(const Duration(hours: 1)).toIso8601String(),
          'method': 'CASH',
          'total_amount': 50.0,
          'allocated_amount': 0.0,
          'credit_amount': 50.0,
          'status': 'posted',
          'notes': 'Mobile receipt',
          'created_at': now.add(const Duration(hours: 1)).toIso8601String(),
        });
        await txn.insert('payments', {
          'id': 'phase54-payment-b',
          'receipt_number': 9102,
          'client_id': clientB,
          'amount': 50.0,
          'date': now.add(const Duration(hours: 1)).toIso8601String(),
          'method': 'cash',
          'accountName': 'Cash',
          'status': 'posted',
          'notes': 'Created on mobile B',
          'isIncome': 1,
        });
      });

      final pushedB = await b.cycle(database: dbB);
      expect(pushedB.acknowledged, greaterThanOrEqualTo(2));
      final pulledA = await a.cycle(database: dbA);
      expect(pulledA.pulled, greaterThanOrEqualTo(2));

      expect(
        (await dbA.query('receipt_headers',
                where: 'receipt_number=?', whereArgs: [9102]))
            .single['client_id'],
        clientA,
      );
      final paymentA = (await dbA.query(
        'payments',
        where: 'id=?',
        whereArgs: ['phase54-payment-b'],
      ))
          .single;
      expect(paymentA['client_id'], clientA);
      expect(paymentA['receipt_number'], 9102);
      expect(paymentA['amount'], 50.0);
      expect(await pending(dbA), 0);
      expect(await pending(dbB), 0);

      final before = server.changes.length;
      await a.cycle(database: dbA);
      await b.cycle(database: dbB);
      expect(server.changes.length, before);
    } finally {
      await a.stop();
      await b.stop();
      await dbA.close();
      await dbB.close();
      DatabaseMigration.useDatabaseForTesting(null);
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
