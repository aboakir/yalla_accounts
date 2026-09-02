import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/core/services/sync/outbox_sync_coordinator.dart';
import 'package:yalla_accounts/core/services/sync/outbox_sync_transport.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';

class _AckTransport implements OutboxSyncTransport {
  final List<String> keys = [];

  @override
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message) async {
    keys.add(message.idempotencyKey);
    return OutboxSyncAck(idempotencyKey: message.idempotencyKey);
  }
}

class _MismatchTransport implements OutboxSyncTransport {
  @override
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message) async {
    return const OutboxSyncAck(idempotencyKey: 'wrong-key');
  }
}

class _OfflineTransport implements OutboxSyncTransport {
  @override
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message) {
    throw const SocketException('offline');
  }
}

Future<void> _enqueue(Database db, String id) {
  return OfflineOutboxService.enqueue(
    db,
    channel: OfflineOutboxService.channelSync,
    operation: 'UPSERT',
    entityType: 'repair',
    entityId: id,
    idempotencyKey: 'repair:$id:create',
    payload: {'entity_id': id},
  ).then((_) {});
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('P04.3 no transport never marks local queued work sent', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await TechnicalTables.createAllTables(db);
    await _enqueue(db, 'r-local');

    final status = SyncStateService(
      pollInterval: const Duration(days: 1),
    );
    final coordinator = OutboxSyncCoordinator(status: status);

    final result = await coordinator.drain(database: db);

    expect(result.skippedNoTransport, isTrue);
    expect(result.sent, 0);
    expect(result.remaining, 1);
    expect(status.snapshot.phase, YallaSyncPhase.localOnly);

    final row = (await db.query(TechnicalTables.outboxTable)).single;
    expect(row['sent'], 0);
    expect(row['status'], 'pending');
  });

  test('P04.3 matching acknowledgement drains exactly once', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await TechnicalTables.createAllTables(db);
    await _enqueue(db, 'r-ack');

    final status = SyncStateService(
      pollInterval: const Duration(days: 1),
    );
    final coordinator = OutboxSyncCoordinator(status: status);
    final transport = _AckTransport();

    final result = await coordinator.drain(
      database: db,
      transportOverride: transport,
    );

    expect(result.sent, 1);
    expect(result.failed, 0);
    expect(result.remaining, 0);
    expect(transport.keys, ['repair:r-ack:create']);
    expect(status.snapshot.phase, YallaSyncPhase.synced);

    final row = (await db.query(TechnicalTables.outboxTable)).single;
    expect(row['sent'], 1);
    expect(row['status'], 'sent');

    final second = await coordinator.drain(
      database: db,
      transportOverride: transport,
    );
    expect(second.sent, 0);
    expect(transport.keys, hasLength(1));
  });

  test('P04.3 mismatched acknowledgement is never treated as sent', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await TechnicalTables.createAllTables(db);
    await _enqueue(db, 'r-mismatch');

    final status = SyncStateService(
      pollInterval: const Duration(days: 1),
    );
    final coordinator = OutboxSyncCoordinator(status: status);

    final result = await coordinator.drain(
      database: db,
      transportOverride: _MismatchTransport(),
    );

    expect(result.sent, 0);
    expect(result.failed, 1);
    expect(result.remaining, 1);
    expect(status.snapshot.phase, YallaSyncPhase.failed);

    final row = (await db.query(TechnicalTables.outboxTable)).single;
    expect(row['sent'], 0);
    expect(row['status'], 'failed');
    expect(row['attempt_count'], 1);
  });

  test('P04.3 socket failure preserves local data and schedules retry',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await TechnicalTables.createAllTables(db);
    await _enqueue(db, 'r-offline');

    final status = SyncStateService(
      pollInterval: const Duration(days: 1),
    );
    final coordinator = OutboxSyncCoordinator(status: status);

    final result = await coordinator.drain(
      database: db,
      transportOverride: _OfflineTransport(),
    );

    expect(result.sent, 0);
    expect(result.failed, 1);
    expect(result.remaining, 1);
    expect(status.snapshot.phase, YallaSyncPhase.offline);

    final row = (await db.query(TechnicalTables.outboxTable)).single;
    expect(row['sent'], 0);
    expect(row['status'], 'failed');
    expect(row['attempt_count'], 1);
    expect(row['next_attempt_at'], isNotNull);
  });
}
