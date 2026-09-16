import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:synchronized/synchronized.dart';

import '../db/db_service.dart';
import '../db/tables/sync_foundation_tables.dart';
import 'sync_state_service.dart';
import 'sync_v3_transport.dart';
import 'unified_sync_queue_service.dart';

typedef SyncV3InboundApplier = Future<void> Function(
  DatabaseExecutor transaction,
  InboundSyncChange change,
);

class UnifiedSyncCycleResult {
  const UnifiedSyncCycleResult(
      {required this.acknowledged,
      required this.conflicts,
      required this.rejected,
      required this.pulled,
      required this.skippedNoTransport});
  final int acknowledged;
  final int conflicts;
  final int rejected;
  final int pulled;
  final bool skippedNoTransport;
}

class UnifiedSyncCoordinatorV3 with WidgetsBindingObserver {
  UnifiedSyncCoordinatorV3(
      {required SyncStateService status,
      this.retryInterval = const Duration(seconds: 30)})
      : _status = status;

  static final instance =
      UnifiedSyncCoordinatorV3(status: SyncStateService.instance);
  final SyncStateService _status;
  final Duration retryInterval;
  final Lock _cycleLock = Lock();
  SyncV3Transport? _transport;
  SyncV3InboundApplier? _inboundApplier;
  Timer? _timer;
  bool _started = false;

  bool get transportConfigured => _transport != null;
  bool get inboundApplyConfigured => _inboundApplier != null;
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final db = await DBService.database;
    await UnifiedSyncQueueService.resetInterruptedSending(db);
    _status.setTransportConfigured(transportConfigured);
    await _status.start();
    await cycle(database: db);
    _timer = Timer.periodic(retryInterval, (_) => unawaited(cycle()));
  }

  void configureTransport(SyncV3Transport transport) {
    _transport = transport;
    _status.setTransportConfigured(true);
    if (_started) unawaited(cycle());
  }

  void clearTransport() {
    _transport = null;
    _status.setTransportConfigured(false);
  }

  void configureInboundApplier(SyncV3InboundApplier applier) {
    _inboundApplier = applier;
    if (_started) unawaited(cycle());
  }

  void clearInboundApplier() => _inboundApplier = null;

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
    await _status.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(cycle());
  }

  Future<UnifiedSyncCycleResult> cycle({Database? database}) {
    return _cycleLock.synchronized(() async {
      final db = database ?? await DBService.database;
      final transport = _transport;
      _status.setTransportConfigured(transport != null);
      if (transport == null) {
        await _status.refresh(database: db);
        return const UnifiedSyncCycleResult(
            acknowledged: 0,
            conflicts: 0,
            rejected: 0,
            pulled: 0,
            skippedNoTransport: true);
      }
      var acknowledged = 0;
      var conflicts = 0;
      var rejected = 0;
      var pulled = 0;
      final rows = await UnifiedSyncQueueService.pendingOutbox(db);
      if (rows.isNotEmpty) {
        try {
          for (final row in rows) {
            await UnifiedSyncQueueService.markSending(
                db, row['outbox_id']!.toString());
          }
          _status.setSyncing(
              pendingCount: rows.length, sendingCount: rows.length);
          final response = await transport.push(rows);
          final byChange = {
            for (final result in response.results) result.changeId: result
          };
          if (byChange.length != rows.length) {
            throw const SyncV3TransportException(
                'Push acknowledgement count mismatch.');
          }
          for (final row in rows) {
            final outboxId = row['outbox_id']!.toString();
            final changeId = row['change_id']!.toString();
            final expectedKey = row['idempotency_key']!.toString();
            final result = byChange[changeId];
            if (result == null || result.idempotencyKey != expectedKey) {
              throw const SyncV3TransportException(
                  'Push acknowledgement identity mismatch.');
            }
            switch (result.disposition) {
              case 'ACKNOWLEDGED':
                final sequence = result.serverSequence;
                if (sequence == null) {
                  throw const SyncV3TransportException(
                      'Missing server sequence.');
                }
                await UnifiedSyncQueueService.markAcknowledged(db, outboxId,
                    serverSequence: sequence);
                acknowledged += 1;
                break;
              case 'CONFLICT':
                final conflictId = result.conflictId;
                if (conflictId == null || conflictId.isEmpty) {
                  throw const SyncV3TransportException(
                      'Missing conflict identifier.');
                }
                await UnifiedSyncQueueService.markConflict(db, outboxId,
                    conflictId: conflictId);
                conflicts += 1;
                break;
              case 'REJECTED':
                await UnifiedSyncQueueService.markRejected(db, outboxId,
                    error: result.errorCode ?? 'SYNC_CHANGE_REJECTED');
                rejected += 1;
                break;
              default:
                throw const SyncV3TransportException(
                    'Unknown push disposition.');
            }
          }
        } catch (error) {
          await _restoreSending(db, rows, error);
          _projectError(error);
          return UnifiedSyncCycleResult(
              acknowledged: acknowledged,
              conflicts: conflicts,
              rejected: rejected,
              pulled: pulled,
              skippedNoTransport: false);
        }
      }
      final applier = _inboundApplier;
      if (applier != null) {
        try {
          for (var page = 0; page < 5; page++) {
            final checkpoint = await UnifiedSyncQueueService.checkpointFor(
              db,
              (await _currentOrganization(db)),
            );
            final response = await transport.pull(
              afterServerSequence: checkpoint,
            );
            if (response.fromSequence != checkpoint ||
                response.nextSequence < checkpoint) {
              throw const SyncV3TransportException('Pull checkpoint mismatch.');
            }
            final inbound = response.changes
                .map((change) => InboundSyncChange(
                      serverSequence: change.serverSequence,
                      changeId: change.changeId,
                      entityType: change.entityType,
                      entityId: change.entityId,
                      entityUuid: change.entityUuid,
                      operation: change.operation,
                      revision: change.revision,
                      occurredAt: change.occurredAt,
                      payload: change.payload,
                    ))
                .toList(growable: false);
            if (inbound.isNotEmpty) {
              await UnifiedSyncQueueService.applyInboundBatch(
                db,
                organizationId: await _currentOrganization(db),
                changes: inbound,
                apply: (txn, change) async {
                  final local = await txn.query(
                    SyncFoundationTables.changes,
                    columns: ['change_id'],
                    where: 'change_id=? AND origin=\'local\'',
                    whereArgs: [change.changeId],
                    limit: 1,
                  );
                  if (local.isEmpty) await applier(txn, change);
                },
              );
              pulled += inbound.length;
            }
            if (!response.hasMore) break;
          }
        } catch (error) {
          _projectError(error);
          return UnifiedSyncCycleResult(
              acknowledged: acknowledged,
              conflicts: conflicts,
              rejected: rejected,
              pulled: pulled,
              skippedNoTransport: false);
        }
      }

      await _status.refresh(database: db);
      return UnifiedSyncCycleResult(
          acknowledged: acknowledged,
          conflicts: conflicts,
          rejected: rejected,
          pulled: pulled,
          skippedNoTransport: false);
    });
  }

  static Future<String> _currentOrganization(DatabaseExecutor db) async {
    final rows = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id=1',
      limit: 1,
    );
    final value =
        rows.isEmpty ? '' : rows.single['organization_id']?.toString() ?? '';
    if (value.isEmpty) throw StateError('SYNC_ORGANIZATION_IDENTITY_MISSING');
    return value;
  }

  static Future<void> _restoreSending(
    DatabaseExecutor db,
    List<Map<String, Object?>> rows,
    Object error,
  ) async {
    for (final row in rows) {
      final id = row['outbox_id']!.toString();
      final current = await db.query(
        'sync_outbox',
        columns: ['state'],
        where: 'outbox_id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isNotEmpty && current.single['state'] == 'SENDING') {
        await UnifiedSyncQueueService.returnToPending(db, id,
            error: error.toString());
      }
    }
  }

  void _projectError(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is OSError) {
      _status.setOffline(error.toString());
    } else {
      _status.setFailed(error.toString());
    }
  }
}
