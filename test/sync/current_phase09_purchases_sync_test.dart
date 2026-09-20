import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/purchase_invoices_table.dart';
import 'package:yalla_accounts/core/services/db/tables/purchase_payments_table.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_inbound_router.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

const org = '11111111-1111-4111-8111-111111111111';

class _MemorySyncServer implements SyncV3Transport {
  final List<SyncV3PullChange> changes = [];
  final Map<String, int> sequences = {};
  int sequence = 0;

  @override
  bool get isConfigured => true;
  @override
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows) async {
    final results = <SyncV3PushResult>[];
    for (final row in rows) {
      final changeId = row['change_id']!.toString();
      final current = sequences[changeId];
      final serverSequence = current ?? ++sequence;
      if (current == null) {
        sequences[changeId] = serverSequence;
        changes.add(SyncV3PullChange(
          serverSequence: serverSequence,
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
        serverSequence: serverSequence,
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
        .where((change) => change.serverSequence > afterServerSequence)
        .take(limit)
        .toList(growable: false);
    final next =
        available.isEmpty ? afterServerSequence : available.last.serverSequence;
    return SyncV3PullResponse(
      fromSequence: afterServerSequence,
      nextSequence: next,
      hasMore: changes.any((change) => change.serverSequence > next),
      changes: available,
    );
  }
}

Future<Database> _openDeviceDb(
  String path,
  String deviceId, {
  bool preseed = false,
}) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
    'CREATE TABLE organization_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT NOT NULL)',
  );
  await db.insert(
    'organization_identity',
    {'singleton_id': 1, 'organization_id': org},
  );
  await db.execute(
    'CREATE TABLE installation_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT NOT NULL,device_id TEXT NOT NULL)',
  );
  await db.insert('installation_identity', {
    'singleton_id': 1,
    'organization_id': org,
    'device_id': deviceId,
  });
  await db.execute('''CREATE TABLE clients(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL,
    phone TEXT,email TEXT,address TEXT,notes TEXT,account_id INTEGER
  )''');
  await db.execute('''CREATE TABLE suppliers(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,pid TEXT,phone TEXT,address TEXT,account_id INTEGER
  )''');
  await db.execute('''CREATE TABLE accounts(
    id INTEGER PRIMARY KEY,code TEXT,name TEXT,type TEXT,
    normal_balance TEXT,report_class TEXT,is_postable INTEGER,
    is_system INTEGER,is_active INTEGER,parent_id INTEGER)''');
  await PartyTables.ensure(db);
  await PurchaseInvoicesTable.createAllTables(db);
  await PurchasePaymentsTable.createAllTables(db);
  if (preseed) {
    await db.insert('suppliers', {
      'name': 'Local Dummy Supplier',
      'phone': '',
      'address': '',
    });
  }
  await SyncFoundationTables.ensure(db);
  await UnifiedSyncTables.ensure(db);
  return db;
}

Future<int> _pendingCount(Database db) async {
  final rows = await db.rawQuery(
    "SELECT COUNT(*) AS c FROM sync_outbox WHERE state='PENDING'",
  );
  return (rows.single['c'] as num).toInt();
}

Future<Map<String, Object?>> _partyByName(
  Database db,
  String name,
) async {
  return Map<String, Object?>.from((await db.query(
    'parties',
    where: 'display_name=?',
    whereArgs: [name],
  ))
      .single);
}

Future<int> _supplierIdForParty(Database db, String partyId) async {
  final role = (await db.query(
    'party_roles',
    columns: const ['legacy_id'],
    where: 'party_id=? AND role=?',
    whereArgs: [partyId, 'SUPPLIER'],
  ))
      .single;
  return int.parse(role['legacy_id']!.toString());
}

Future<String> _entityUuid(
  Database db,
  String entityType,
  String localId,
) async {
  final row = (await db.query(
    SyncFoundationTables.registry,
    columns: const ['entity_uuid'],
    where: 'entity_type=? AND local_id=?',
    whereArgs: [entityType, localId],
  ))
      .single;
  return row['entity_uuid']!.toString();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
      'Phase 09 Purchase hierarchy replicates by stable supplier and parent UUIDs',
      () async {
    final root =
        await Directory.systemTemp.createTemp('phase09_purchase_sync_');
    final dbA = await _openDeviceDb(
      '${root.path}/a.sqlite',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final dbB = await _openDeviceDb(
      '${root.path}/b.sqlite',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      preseed: true,
    );
    final server = _MemorySyncServer();
    final coordinatorA = UnifiedSyncCoordinatorV3(status: SyncStateService());
    final coordinatorB = UnifiedSyncCoordinatorV3(status: SyncStateService());
    coordinatorA.configureTransport(server);
    coordinatorB.configureTransport(server);
    coordinatorB.configureInboundApplier(UnifiedSyncInboundRouter.apply);

    try {
      await PartyFinancialService.createParty(
        name: 'Purchase Supplier',
        phone: '0599000001',
        address: 'Bethlehem',
        customer: false,
        supplier: true,
        database: dbA,
      );
      expect(await _pendingCount(dbA), 1);
      expect((await coordinatorA.cycle(database: dbA)).acknowledged, 1);
      expect((await coordinatorB.cycle(database: dbB)).pulled, 1);
      final partyA = await _partyByName(dbA, 'Purchase Supplier');
      final supplierA = await _supplierIdForParty(
        dbA,
        partyA['id']!.toString(),
      );
      final partyUuid = await _entityUuid(
        dbA,
        'party',
        partyA['id']!.toString(),
      );
      final partyIdentityB = (await dbB.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND entity_uuid=?',
        whereArgs: ['party', partyUuid],
      ))
          .single;
      final supplierB = await _supplierIdForParty(
        dbB,
        partyIdentityB['local_id']!.toString(),
      );
      expect(supplierB, isNot(supplierA));

      const invoiceIdA = 'purchase-local-a';
      final invoiceDate = DateTime.utc(2026, 9, 16, 19).toIso8601String();
      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.insert('purchase_invoices', {
          'id': invoiceIdA,
          'supplier_id': supplierA,
          'supplier_party_uuid': partyUuid,
          'is_active': 1,
          'purchase_type': 'PARTS',
          'subtotal': 120.0,
          'vat': 0.0,
          'total': 120.0,
          'amount_total': 120.0,
          'paid_total': 77.0,
          'remaining': 43.0,
          'status': 'PARTIAL',
          'date': invoiceDate,
          'note': 'Phase09 purchase',
          'method': 'credit',
          'gl_entry_id': 9001,
          'created_at': invoiceDate,
          'updated_at': invoiceDate,
        });
      });
      final invoiceUuid = await _entityUuid(
        dbA,
        'purchase_invoice',
        invoiceIdA,
      );
      expect(
        (await coordinatorA.cycle(database: dbA)).acknowledged,
        greaterThanOrEqualTo(1),
      );
      expect(
        (await coordinatorB.cycle(database: dbB)).pulled,
        greaterThanOrEqualTo(1),
      );
      final invoiceIdentityB = (await dbB.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND entity_uuid=?',
        whereArgs: ['purchase_invoice', invoiceUuid],
      ))
          .single;
      final invoiceIdB = invoiceIdentityB['local_id']!.toString();
      expect(invoiceIdB, isNot(invoiceIdA));
      final invoiceB = (await dbB.query(
        'purchase_invoices',
        where: 'id=?',
        whereArgs: [invoiceIdB],
      ))
          .single;
      expect(invoiceB['supplier_id'], supplierB);
      expect(invoiceB['supplier_party_uuid'], partyUuid);
      expect(invoiceB['gl_entry_id'], isNull);
      expect(invoiceB['paid_total'], 0.0);
      expect(invoiceB['remaining'], 120.0);
      expect(invoiceB['status'], 'UNPAID');
      final invoiceWire = server.changes.singleWhere(
        (change) =>
            change.entityType == 'purchase_invoice' &&
            change.entityUuid == invoiceUuid,
      );
      expect(invoiceWire.payload['supplier_party_uuid'], partyUuid);
      for (final forbidden in const [
        'supplier_id',
        'gl_entry_id',
        'paid_total',
        'remaining',
        'status',
      ]) {
        expect(invoiceWire.payload.containsKey(forbidden), isFalse);
      }
      expect(await _pendingCount(dbB), 0);

      const lineIdA = 'purchase-line-local-a';
      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.insert('purchase_invoice_lines', {
          'id': lineIdA,
          'invoice_id': invoiceIdA,
          'item': 'Front lamp',
          'item_name': 'Front lamp',
          'qty': 2.0,
          'unit_price': 60.0,
          'price': 60.0,
          'total': 120.0,
          'category': 'PARTS',
          'note': 'OEM',
        });
      });
      final lineUuid = await _entityUuid(
        dbA,
        'purchase_invoice_line',
        lineIdA,
      );
      expect(
        (await coordinatorA.cycle(database: dbA)).acknowledged,
        greaterThanOrEqualTo(1),
      );
      expect(
        (await coordinatorB.cycle(database: dbB)).pulled,
        greaterThanOrEqualTo(1),
      );
      final lineIdentityB = (await dbB.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND entity_uuid=?',
        whereArgs: ['purchase_invoice_line', lineUuid],
      ))
          .single;
      final lineIdB = lineIdentityB['local_id']!.toString();
      expect(lineIdB, isNot(lineIdA));
      final lineB = (await dbB.query(
        'purchase_invoice_lines',
        where: 'id=?',
        whereArgs: [lineIdB],
      ))
          .single;
      expect(lineB['invoice_id'], invoiceIdB);
      expect(lineB['item_name'], 'Front lamp');
      expect(lineB['total'], 120.0);
      final lineWire = server.changes.singleWhere(
        (change) =>
            change.entityType == 'purchase_invoice_line' &&
            change.entityUuid == lineUuid,
      );
      expect(lineWire.payload['purchase_invoice_entity_uuid'], invoiceUuid);
      expect(lineWire.payload.containsKey('id'), isFalse);
      expect(lineWire.payload.containsKey('invoice_id'), isFalse);
      expect(await _pendingCount(dbB), 0);

      const paymentIdA = 'purchase-payment-local-a';
      final paymentDate = DateTime.utc(2026, 9, 16, 19, 10).toIso8601String();
      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.insert('purchase_payments', {
          'id': paymentIdA,
          'invoice_id': invoiceIdA,
          'purchase_invoice_entity_uuid': null,
          'amount': 20.0,
          'date': paymentDate,
          'method': 'CASH',
          'note': 'Operational payment only',
          'gl_entry_id': 777,
          'created_at': paymentDate,
          'updated_at': paymentDate,
        });
      });
      final paymentUuid = await _entityUuid(
        dbA,
        'purchase_payment',
        paymentIdA,
      );
      expect(
        (await coordinatorA.cycle(database: dbA)).acknowledged,
        greaterThanOrEqualTo(1),
      );
      expect(
        (await coordinatorB.cycle(database: dbB)).pulled,
        greaterThanOrEqualTo(1),
      );
      final paymentIdentityB = (await dbB.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND entity_uuid=?',
        whereArgs: ['purchase_payment', paymentUuid],
      ))
          .single;
      final paymentIdB = paymentIdentityB['local_id']!.toString();
      expect(paymentIdB, isNot(paymentIdA));
      final paymentB = (await dbB.query(
        'purchase_payments',
        where: 'id=?',
        whereArgs: [paymentIdB],
      ))
          .single;
      expect(paymentB['invoice_id'], invoiceIdB);
      expect(paymentB['purchase_invoice_entity_uuid'], invoiceUuid);
      expect(paymentB['amount'], 20.0);
      expect(paymentB['gl_entry_id'], isNull);
      final paymentWire = server.changes.singleWhere(
        (change) =>
            change.entityType == 'purchase_payment' &&
            change.entityUuid == paymentUuid,
      );
      expect(paymentWire.payload['purchase_invoice_entity_uuid'], invoiceUuid);
      expect(paymentWire.payload.containsKey('id'), isFalse);
      expect(paymentWire.payload.containsKey('invoice_id'), isFalse);
      expect(paymentWire.payload.containsKey('gl_entry_id'), isFalse);
      expect(await _pendingCount(dbB), 0);

      final paymentOutbox = Map<String, Object?>.from((await dbA.query(
        UnifiedSyncTables.outbox,
        where: 'entity_type=? AND entity_uuid=?',
        whereArgs: ['purchase_payment', paymentUuid],
      ))
          .single);
      final beforeRetryCount = server.changes.length;
      final retryResponse = await server.push([paymentOutbox]);
      expect(retryResponse.results.single.serverSequence,
          paymentWire.serverSequence);
      expect(server.changes.length, beforeRetryCount);

      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
          'purchase_invoices',
          {
            'is_active': 0,
            'updated_at': DateTime.utc(2026, 9, 16, 19, 20).toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [invoiceIdA],
        );
      });
      expect(
        (await coordinatorA.cycle(database: dbA)).acknowledged,
        greaterThanOrEqualTo(1),
      );
      expect(
        (await coordinatorB.cycle(database: dbB)).pulled,
        greaterThanOrEqualTo(1),
      );
      var invoiceAfter = (await dbB.query(
        'purchase_invoices',
        where: 'id=?',
        whereArgs: [invoiceIdB],
      ))
          .single;
      expect(invoiceAfter['is_active'], 0);
      final invoiceDelete = server.changes.lastWhere(
        (change) => change.entityUuid == invoiceUuid,
      );
      expect(invoiceDelete.operation, 'DELETE');

      await SyncFoundationService.transaction(dbA, (txn) async {
        await txn.update(
          'purchase_invoices',
          {
            'is_active': 1,
            'note': 'Restored purchase',
            'updated_at': DateTime.utc(2026, 9, 16, 19, 25).toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [invoiceIdA],
        );
      });
      expect(
        (await coordinatorA.cycle(database: dbA)).acknowledged,
        greaterThanOrEqualTo(1),
      );
      expect(
        (await coordinatorB.cycle(database: dbB)).pulled,
        greaterThanOrEqualTo(1),
      );
      invoiceAfter = (await dbB.query(
        'purchase_invoices',
        where: 'id=?',
        whereArgs: [invoiceIdB],
      ))
          .single;
      expect(invoiceAfter['is_active'], 1);
      expect(invoiceAfter['note'], 'Restored purchase');
      final invoiceRestore = server.changes.lastWhere(
        (change) => change.entityUuid == invoiceUuid,
      );
      expect(invoiceRestore.operation, 'UPSERT');
      expect(invoiceRestore.payload['_sync_restore'], true);

      final checkpointBefore = (await dbB.query(
        UnifiedSyncTables.checkpoint,
      ))
          .single['last_server_sequence'];
      final emptyRetry = await coordinatorB.cycle(database: dbB);
      expect(emptyRetry.pulled, 0);
      expect(
        (await dbB.query(UnifiedSyncTables.checkpoint))
            .single['last_server_sequence'],
        checkpointBefore,
      );
      expect(await _pendingCount(dbB), 0);

      final deletePayment = InboundSyncChange(
        serverSequence: (checkpointBefore as num).toInt() + 1,
        changeId: 'payment-delete-denied',
        entityType: 'purchase_payment',
        entityId: paymentIdA,
        entityUuid: paymentUuid,
        operation: 'DELETE',
        revision: 2,
        occurredAt: DateTime.utc(2026, 9, 16, 19, 30),
        payload: {'purchase_invoice_entity_uuid': invoiceUuid},
      );
      await expectLater(
        SyncFoundationService.transaction(
          dbB,
          (txn) => UnifiedSyncInboundRouter.apply(txn, deletePayment),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'SYNC_PURCHASE_PAYMENT_DELETE_DENIED',
          ),
        ),
      );
      expect(
        await dbB.query(
          'purchase_payments',
          where: 'id=?',
          whereArgs: [paymentIdB],
        ),
        hasLength(1),
      );
      expect(await dbB.query('purchase_invoices'), hasLength(1));
      expect(await dbB.query('purchase_invoice_lines'), hasLength(1));
      expect(await dbB.query('purchase_payments'), hasLength(1));
    } finally {
      await dbA.close();
      await dbB.close();
      await root.delete(recursive: true);
    }
  });
}
