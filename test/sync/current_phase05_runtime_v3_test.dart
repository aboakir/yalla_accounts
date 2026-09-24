import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';

const org = '11111111-1111-4111-8111-111111111111';
const installation = '22222222-2222-4222-8222-222222222222';
const device = '33333333-3333-4333-8333-333333333333';

class FakeTransport implements SyncV3Transport {
  FakeTransport({this.conflict = false, this.pullChanges = const []});
  final bool conflict;
  final List<SyncV3PullChange> pullChanges;
  int pushes = 0;
  int pulls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows) async {
    pushes += 1;
    return SyncV3PushResponse(rows
        .map((row) => SyncV3PushResult(
              changeId: row['change_id']!.toString(),
              idempotencyKey: row['idempotency_key']!.toString(),
              disposition: conflict ? 'CONFLICT' : 'ACKNOWLEDGED',
              serverSequence: conflict ? null : pushes,
              conflictId:
                  conflict ? 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' : null,
            ))
        .toList());
  }

  @override
  Future<SyncV3PullResponse> pull(
      {required int afterServerSequence, int limit = 200}) async {
    pulls += 1;
    final all = pullChanges
        .where((c) => c.serverSequence > afterServerSequence)
        .toList();
    final available = all.take(limit).toList(growable: false);
    return SyncV3PullResponse(
      fromSequence: afterServerSequence,
      nextSequence: available.isEmpty
          ? afterServerSequence
          : available.last.serverSequence,
      hasMore: all.length > available.length,
      changes: available,
    );
  }
}

class FakeIdentityService extends DeviceIdentityService {
  FakeIdentityService(this.value) : super();
  final DeviceIdentity value;
  List<int>? lastSigned;

  @override
  Future<DeviceIdentity> ensureCurrent() async => value;

  @override
  Future<DeviceProof> signChallenge(List<int> challenge) async {
    lastSigned = List<int>.from(challenge);
    return DeviceProof(
      deviceId: value.deviceId,
      algorithm: 'ED25519',
      signatureBase64Url: List.filled(86, 'A').join(),
    );
  }
}

Map<String, Object?> _outboxRow(String changeId) => {
      'outbox_id': changeId,
      'change_id': changeId,
      'organization_id': org,
      'entity_type': 'repair',
      'entity_id': 'r1',
      'entity_uuid': '44444444-4444-4444-8444-444444444444',
      'operation': 'UPSERT',
      'base_revision': 0,
      'revision': 1,
      'idempotency_key': 'sync-change:$changeId',
      'occurred_at': '2026-09-16T10:00:00.000Z',
      'payload_json': jsonEncode({'id': 'r1', 'notes': 'x'}),
    };
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('coordinator acknowledges v3 outbox exactly once', () async {
    final dir = await Directory.systemTemp.createTemp('phase05_runtime_push_');
    final db = await databaseFactoryFfi.openDatabase('${dir.path}/db.sqlite');
    try {
      await db.execute(
          'CREATE TABLE organization_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT)');
      await db.insert(
          'organization_identity', {'singleton_id': 1, 'organization_id': org});
      await db.execute(
          'CREATE TABLE installation_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT,device_id TEXT)');
      await db.insert('installation_identity',
          {'singleton_id': 1, 'organization_id': org, 'device_id': device});
      await db.execute(
          'CREATE TABLE repairs(id TEXT PRIMARY KEY,notes TEXT,status TEXT,fileValue REAL)');
      await db.execute('''CREATE TABLE accounts(
        id INTEGER PRIMARY KEY,code TEXT,name TEXT,type TEXT,
        normal_balance TEXT,report_class TEXT,is_postable INTEGER,
        is_system INTEGER,is_active INTEGER,parent_id INTEGER)''');
      await db.execute('''CREATE TABLE party_roles(
        party_id INTEGER NOT NULL,role TEXT NOT NULL,legacy_id INTEGER)''');
      await TechnicalTables.createAllTables(db);
      await SyncFoundationTables.ensure(db);
      await UnifiedSyncTables.ensure(db);
      await db.insert('repairs',
          {'id': 'r1', 'notes': 'created', 'status': 'active', 'fileValue': 1});

      final transport = FakeTransport();
      final coordinator = UnifiedSyncCoordinatorV3(status: SyncStateService());
      coordinator.configureTransport(transport);
      final first = await coordinator.cycle(database: db);
      expect(first.acknowledged, 1);
      expect(transport.pushes, 1);
      final row = (await db.query(UnifiedSyncTables.outbox)).single;
      expect(row['state'], 'ACKNOWLEDGED');
      expect(row['server_sequence'], 1);

      final second = await coordinator.cycle(database: db);
      expect(second.acknowledged, 0);
      expect(transport.pushes, 1);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
  test('pull waits for applier then advances checkpoint atomically', () async {
    final dir = await Directory.systemTemp.createTemp('phase05_runtime_pull_');
    final db = await databaseFactoryFfi.openDatabase('${dir.path}/db.sqlite');
    try {
      await db.execute(
          'CREATE TABLE organization_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT)');
      await db.insert(
          'organization_identity', {'singleton_id': 1, 'organization_id': org});
      await db.execute(
          'CREATE TABLE installation_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT,device_id TEXT)');
      await db.insert('installation_identity',
          {'singleton_id': 1, 'organization_id': org, 'device_id': device});
      await db.execute(
          'CREATE TABLE repairs(id TEXT PRIMARY KEY,notes TEXT,status TEXT,fileValue REAL)');
      await db.execute(
          'CREATE TABLE applied_remote(id TEXT PRIMARY KEY,notes TEXT)');
      await db.execute('''CREATE TABLE accounts(
        id INTEGER PRIMARY KEY,code TEXT,name TEXT,type TEXT,
        normal_balance TEXT,report_class TEXT,is_postable INTEGER,
        is_system INTEGER,is_active INTEGER,parent_id INTEGER)''');
      await db.execute('''CREATE TABLE party_roles(
        party_id INTEGER NOT NULL,role TEXT NOT NULL,legacy_id INTEGER)''');
      await TechnicalTables.createAllTables(db);
      await SyncFoundationTables.ensure(db);
      await UnifiedSyncTables.ensure(db);

      final remote = SyncV3PullChange(
        serverSequence: 7,
        changeId: '77777777-7777-4777-8777-777777777777',
        organizationId: org,
        entityType: 'repair',
        entityId: 'remote-1',
        entityUuid: '88888888-8888-4888-8888-888888888888',
        operation: 'UPSERT',
        revision: 1,
        occurredAt: DateTime.utc(2026, 9, 16, 10),
        payload: const {'id': 'remote-1', 'notes': 'from server'},
      );
      final transport = FakeTransport(pullChanges: [remote]);
      final coordinator = UnifiedSyncCoordinatorV3(status: SyncStateService());
      coordinator.configureTransport(transport);
      await coordinator.cycle(database: db);
      expect(transport.pulls, 0);
      expect(await UnifiedSyncQueueService.checkpointFor(db, org), 0);

      coordinator.configureInboundApplier((txn, change) async {
        await txn.insert('applied_remote', {
          'id': change.entityId,
          'notes': change.payload['notes']?.toString(),
        });
      });
      final result = await coordinator.cycle(database: db);
      expect(result.pulled, 1);
      expect(await UnifiedSyncQueueService.checkpointFor(db, org), 7);
      expect(await db.query('applied_remote'), hasLength(1));
      await coordinator.cycle(database: db);
      expect(await db.query('applied_remote'), hasLength(1));
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
  test('bootstrap from checkpoint zero drains more than five pull pages',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('phase05_bootstrap_pages_');
    final db = await databaseFactoryFfi.openDatabase('${dir.path}/db.sqlite');
    try {
      await db.execute(
          'CREATE TABLE organization_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT)');
      await db.insert(
          'organization_identity', {'singleton_id': 1, 'organization_id': org});
      await db.execute(
          'CREATE TABLE installation_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT,device_id TEXT)');
      await db.insert('installation_identity',
          {'singleton_id': 1, 'organization_id': org, 'device_id': device});
      await db.execute(
          'CREATE TABLE applied_remote(id TEXT PRIMARY KEY,notes TEXT)');
      await db.execute('''CREATE TABLE accounts(
        id INTEGER PRIMARY KEY,code TEXT,name TEXT,type TEXT,
        normal_balance TEXT,report_class TEXT,is_postable INTEGER,
        is_system INTEGER,is_active INTEGER,parent_id INTEGER)''');
      await db.execute('''CREATE TABLE party_roles(
        party_id INTEGER NOT NULL,role TEXT NOT NULL,legacy_id INTEGER)''');
      await TechnicalTables.createAllTables(db);
      await SyncFoundationTables.ensure(db);
      await UnifiedSyncTables.ensure(db);

      final remote = List<SyncV3PullChange>.generate(1201, (index) {
        final sequence = index + 1;
        final suffix = sequence.toString().padLeft(12, '0');
        return SyncV3PullChange(
          serverSequence: sequence,
          changeId: '10000000-0000-4000-8000-$suffix',
          organizationId: org,
          entityType: 'repair',
          entityId: 'remote-$sequence',
          entityUuid: '20000000-0000-4000-8000-$suffix',
          operation: 'UPSERT',
          revision: 1,
          occurredAt: DateTime.utc(2026, 9, 16, 10),
          payload: {'notes': 'bootstrap-$sequence'},
        );
      });
      final transport = FakeTransport(pullChanges: remote);
      final coordinator = UnifiedSyncCoordinatorV3(status: SyncStateService());
      coordinator.configureTransport(transport);
      coordinator.configureInboundApplier((txn, change) async {
        await txn.insert('applied_remote', {
          'id': change.entityId,
          'notes': change.payload['notes']?.toString(),
        });
      });

      final result = await coordinator.cycle(database: db);
      expect(result.pulled, 1201);
      expect(await UnifiedSyncQueueService.checkpointFor(db, org), 1201);
      expect(transport.pulls, 7);
      expect(await db.query('applied_remote'), hasLength(1201));
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('HTTP v3 transport signs canonical request and sends exact headers',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? received;
    late HttpHeaders receivedHeaders;
    final done = server.listen((request) async {
      receivedHeaders = request.headers;
      received = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'sync_contract_version': 3,
        'results': [
          {
            'change_id': '99999999-9999-4999-8999-999999999999',
            'idempotency_key':
                'sync-change:99999999-9999-4999-8999-999999999999',
            'disposition': 'ACKNOWLEDGED',
            'server_sequence': 11,
          }
        ],
        'server_time': '2026-09-16T10:00:00.000Z',
      }));
      await request.response.close();
    });
    final identity = DeviceIdentity(
      organizationId: org,
      installationId: installation,
      deviceId: device,
      publicKeyBase64Url: List.filled(43, 'A').join(),
      publicKeySha256: List.filled(64, 'a').join(),
      fingerprintSha256: List.filled(64, 'b').join(),
      platform: 'Windows',
      appVersion: '1.0.0',
      identityGeneration: 1,
      bindingState: 'BOUND',
      createdAt: DateTime.utc(2026, 9, 16),
    );
    final signer = FakeIdentityService(identity);
    final transport = HttpSyncV3Transport(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      bearerTokenProvider: () async => 'test-token',
      deviceIdentityService: signer,
      allowInsecureLoopbackForTesting: true,
    );
    final response = await transport.push([
      _outboxRow('99999999-9999-4999-8999-999999999999'),
    ]);
    expect(response.results.single.serverSequence, 11);
    expect(receivedHeaders.value('x-yalla-sync-contract-version'), '3');
    expect(receivedHeaders.value('x-yalla-installation-id'), installation);
    expect(receivedHeaders.value(HttpHeaders.authorizationHeader),
        'Bearer test-token');
    final proof = Map<String, dynamic>.from(received!['device_proof'] as Map);
    expect(proof['algorithm'], 'ED25519');
    expect(
        signer.lastSigned!
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        proof['body_sha256']);
    await server.close(force: true);
    await done.cancel();
  });
}
