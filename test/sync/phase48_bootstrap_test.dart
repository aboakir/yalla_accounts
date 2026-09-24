import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';

const org = '48111111-1111-4111-8111-111111111111';

class BootstrapServer implements SyncV3Transport, SyncV3BootstrapTransport {
  BootstrapServer({this.failOnceOnSecondPage = false});
  final bool failOnceOnSecondPage;
  var bootstrapCalls = 0;
  var pullCalls = 0;
  var failed = false;

  final changes = <SyncV3PullChange>[
    _change(2, 'a'),
    _change(5, 'b'),
    _change(9, 'c'),
  ];

  static SyncV3PullChange _change(int sequence, String suffix) =>
      SyncV3PullChange(
        serverSequence: sequence,
        changeId: '48000000-0000-4000-8000-00000000000$suffix',
        organizationId: org,
        entityType: 'repair',
        entityId: 'repair-$suffix',
        entityUuid: '49000000-0000-4000-8000-00000000000$suffix',
        operation: 'UPSERT',
        revision: 1,
        occurredAt: DateTime.utc(2026, 9, 25, 1, sequence),
        payload: {'notes': 'bootstrap-$suffix'},
      );

  @override
  bool get isConfigured => true;

  @override
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows) async =>
      const SyncV3PushResponse([]);

  @override
  Future<SyncV3BootstrapResponse> bootstrap({
    int cursorServerSequence = 0,
    int? snapshotServerSequence,
    int limit = 200,
  }) async {
    bootstrapCalls++;
    if (failOnceOnSecondPage && cursorServerSequence > 0 && !failed) {
      failed = true;
      throw const SyncV3TransportException('simulated server outage');
    }
    final snapshot = snapshotServerSequence ?? 9;
    final available = changes
        .where((c) =>
            c.serverSequence > cursorServerSequence &&
            c.serverSequence <= snapshot)
        .take(2)
        .toList(growable: false);
    final next = available.isEmpty
        ? cursorServerSequence
        : available.last.serverSequence;
    final hasMore = changes.any(
      (c) => c.serverSequence > next && c.serverSequence <= snapshot,
    );
    return SyncV3BootstrapResponse(
      snapshotSequence: snapshot,
      cursorSequence: cursorServerSequence,
      nextCursorSequence: next,
      hasMore: hasMore,
      changes: available,
    );
  }

  @override
  Future<SyncV3PullResponse> pull({
    required int afterServerSequence,
    int limit = 200,
  }) async {
    pullCalls++;
    return SyncV3PullResponse(
      fromSequence: afterServerSequence,
      nextSequence: afterServerSequence,
      hasMore: false,
      changes: const [],
    );
  }
}

Future<Database> openFixture(Directory dir) async {
  final db = await databaseFactoryFfi.openDatabase('${dir.path}/db.sqlite');
  await db.execute(
    'CREATE TABLE organization_identity('
    'singleton_id INTEGER PRIMARY KEY,organization_id TEXT)',
  );
  await db.insert(
    'organization_identity',
    {'singleton_id': 1, 'organization_id': org},
  );
  await db.execute(
    'CREATE TABLE installation_identity('
    'singleton_id INTEGER PRIMARY KEY,organization_id TEXT,device_id TEXT)',
  );
  await db.execute(
    'CREATE TABLE accounts('
    'id INTEGER PRIMARY KEY,code TEXT,name TEXT,type TEXT,'
    'normal_balance TEXT,report_class TEXT,is_postable INTEGER,'
    'is_system INTEGER,is_active INTEGER,parent_id INTEGER)',
  );
  await db.execute(
    'CREATE TABLE party_roles('
    'party_id INTEGER NOT NULL,role TEXT NOT NULL,legacy_id INTEGER)',
  );
  await db.execute(
    'CREATE TABLE applied_remote(id TEXT PRIMARY KEY,notes TEXT)',
  );
  await TechnicalTables.createAllTables(db);
  await SyncFoundationTables.ensure(db);
  await UnifiedSyncTables.ensure(db);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('phase48 explicit bootstrap builds SQLite and marks READY', () async {
    final dir = await Directory.systemTemp.createTemp('phase48_bootstrap_');
    final db = await openFixture(dir);
    final server = BootstrapServer();
    final coordinator = UnifiedSyncCoordinatorV3(status: SyncStateService());
    coordinator.configureTransport(server);
    coordinator.configureInboundApplier((txn, change) async {
      await txn.insert('applied_remote', {
        'id': change.entityId,
        'notes': change.payload['notes']?.toString(),
      });
    });
    try {
      final result = await coordinator.cycle(database: db);
      expect(result.pulled, 3);
      expect(await db.query('applied_remote'), hasLength(3));
      expect(
        (await db.query(UnifiedSyncTables.bootstrapState)).single['state'],
        'READY',
      );
      expect(
        (await db.query(UnifiedSyncTables.checkpoint))
            .single['last_server_sequence'],
        9,
      );
      expect(server.bootstrapCalls, 2);
      expect(server.pullCalls, 1);
    } finally {
      await coordinator.stop();
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('phase48 bootstrap resumes after mid-snapshot outage', () async {
    final dir =
        await Directory.systemTemp.createTemp('phase48_bootstrap_resume_');
    final db = await openFixture(dir);
    final server = BootstrapServer(failOnceOnSecondPage: true);
    final coordinator = UnifiedSyncCoordinatorV3(status: SyncStateService());
    coordinator.configureTransport(server);
    coordinator.configureInboundApplier((txn, change) async {
      await txn.insert(
        'applied_remote',
        {'id': change.entityId, 'notes': change.payload['notes']?.toString()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
    try {
      final first = await coordinator.cycle(database: db);
      expect(first.pulled, 0);
      expect(await db.query('applied_remote'), hasLength(2));
      final state = (await db.query(UnifiedSyncTables.bootstrapState)).single;
      expect(state['state'], 'IN_PROGRESS');
      expect(state['cursor_server_sequence'], 5);

      final second = await coordinator.cycle(database: db);
      expect(second.pulled, 1);
      expect(await db.query('applied_remote'), hasLength(3));
      expect(
        (await db.query(UnifiedSyncTables.bootstrapState)).single['state'],
        'READY',
      );
      expect(
        (await db.query(UnifiedSyncTables.checkpoint))
            .single['last_server_sequence'],
        9,
      );
    } finally {
      await coordinator.stop();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
