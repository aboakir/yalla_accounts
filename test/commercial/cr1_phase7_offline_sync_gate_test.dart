import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/core/services/sync/outbox_sync_coordinator.dart';
import 'package:yalla_accounts/core/services/sync/outbox_sync_transport.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';

class _LostAckThenReplayTransport implements OutboxSyncTransport {
  final acceptedKeys = <String>{};
  var calls = 0;

  @override
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message) async {
    calls += 1;
    acceptedKeys.add(message.idempotencyKey);
    if (calls == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return OutboxSyncAck(idempotencyKey: message.idempotencyKey);
  }
}

Future<Database> _open(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
      'CREATE TABLE IF NOT EXISTS organization_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT)');
  await db.insert(
      'organization_identity',
      {
        'singleton_id': 1,
        'organization_id': '11111111-1111-4111-8111-111111111111'
      },
      conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.execute(
      'CREATE TABLE IF NOT EXISTS installation_identity(singleton_id INTEGER PRIMARY KEY,organization_id TEXT,device_id TEXT)');
  await db.insert(
      'installation_identity',
      {
        'singleton_id': 1,
        'organization_id': '11111111-1111-4111-8111-111111111111',
        'device_id': '22222222-2222-4222-8222-222222222222'
      },
      conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.execute(
      'CREATE TABLE IF NOT EXISTS repairs(id TEXT PRIMARY KEY,notes TEXT,status TEXT,fileValue REAL)');
  await db.execute(
      'CREATE TABLE IF NOT EXISTS gl_entries(id INTEGER PRIMARY KEY,source TEXT,source_id TEXT)');
  await db.execute(
      'CREATE TABLE IF NOT EXISTS gl_lines(id INTEGER PRIMARY KEY,entry_id INTEGER,debit REAL,credit REAL)');
  await TechnicalTables.createAllTables(db);
  await SyncFoundationTables.ensure(db);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
      'offline change survives restart and missing outbox is materialized once',
      () async {
    final dir = await Directory.systemTemp.createTemp('phase7-offline-');
    final path = '${dir.path}/sync.db';
    var db = await _open(path);
    await db.insert('repairs', {
      'id': 'offline-repair',
      'notes': 'saved without network',
      'status': 'QUOTE',
      'fileValue': 100.0,
    });
    expect(await SyncFoundationService.materializeMissingOutbox(db), 1);
    expect(await SyncFoundationService.materializeMissingOutbox(db), 0);
    expect((await OfflineOutboxService.queueStats(db)).unsent, 1);
    await db.close();

    db = await _open(path);
    expect((await OfflineOutboxService.queueStats(db)).unsent, 1);
    final linked = await db.query(SyncFoundationTables.outboxLinks);
    expect(linked, hasLength(1));
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
      'lost acknowledgement retries same mutation without duplicate remote apply',
      () async {
    final db = await _open(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.insert('repairs', {
      'id': 'timeout-repair',
      'notes': 'timeout',
      'status': 'QUOTE',
      'fileValue': 50.0,
    });
    await SyncFoundationService.materializeMissingOutbox(db);
    final transport = _LostAckThenReplayTransport();
    final status = SyncStateService(pollInterval: const Duration(days: 1));
    final coordinator = OutboxSyncCoordinator(
      status: status,
      sendTimeout: const Duration(milliseconds: 20),
    );
    final first = await coordinator.drain(
      database: db,
      transportOverride: transport,
    );
    expect(first.sent, 0);
    expect(first.failed, 1);
    expect(transport.acceptedKeys, hasLength(1));
    final row = (await db.query(TechnicalTables.outboxTable)).single;
    expect(row['status'], 'failed');
    await db.update(
      TechnicalTables.outboxTable,
      {'next_attempt_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id=?',
      whereArgs: [row['id']],
    );
    final second = await coordinator.drain(
      database: db,
      transportOverride: transport,
    );
    expect(second.sent, 1);
    expect(second.remaining, 0);
    expect(transport.calls, 2);
    expect(transport.acceptedKeys, hasLength(1));
    final finalRow = (await db.query(TechnicalTables.outboxTable)).single;
    expect(finalRow['status'], 'sent');
    expect(finalRow['sent'], 1);
    final ackEvents = await db.query(
      SyncFoundationTables.changes,
      where: "origin='acknowledgement'",
    );
    expect(ackEvents, hasLength(1));
  });

  test('financial remote candidate is quarantined and never posts GL',
      () async {
    final db = await _open(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.insert('repairs', {
      'id': 'financial-repair',
      'notes': 'local',
      'status': 'QUOTE',
      'fileValue': 100.0,
    });
    final identity = await SyncFoundationService.identityFor(
      db,
      entityType: 'repair',
      localId: 'financial-repair',
    );
    final beforeRepair = (await db.query('repairs')).single;
    final candidate = RemoteSyncCandidate(
      changeId: '33333333-3333-4333-8333-333333333333',
      organizationId: '11111111-1111-4111-8111-111111111111',
      deviceId: '44444444-4444-4444-8444-444444444444',
      userId: 'remote-user',
      entityUuid: identity!['entity_uuid'] as String,
      entityType: 'repair',
      baseRevision: identity['revision'] as int,
      operation: SyncChangeOperation.updated,
      occurredAt: DateTime.utc(2026, 9, 15, 8),
      snapshot: const {
        'id': 'financial-repair',
        'notes': 'remote',
        'status': 'QUOTE',
        'fileValue': 120.0,
      },
    );
    final first =
        await SyncFoundationService.quarantineCandidate(db, candidate);
    expect(first.requiresReview, isTrue);
    expect(first.reasons, contains('financial_value_difference'));
    expect(first.applied, isFalse);
    expect((await db.query('repairs')).single, beforeRepair);
    expect(await db.query('gl_entries'), isEmpty);
    expect(await db.query('gl_lines'), isEmpty);

    final retry =
        await SyncFoundationService.quarantineCandidate(db, candidate);
    expect(retry.duplicate, isTrue);
    expect(retry.candidateId, first.candidateId);
    expect(await db.query(SyncFoundationTables.candidates), hasLength(1));
    expect(await db.query(SyncFoundationTables.conflicts), hasLength(1));
    expect(await db.query('gl_entries'), isEmpty);
  });
}
