import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:synchronized/synchronized.dart';

import '../db_service.dart';
import '../offline_outbox_service.dart';
import 'outbox_sync_transport.dart';
import 'sync_foundation_service.dart';
import 'sync_state_service.dart';

class OutboxDrainResult {
  const OutboxDrainResult({
    required this.sent,
    required this.failed,
    required this.remaining,
    required this.skippedNoTransport,
  });

  final int sent;
  final int failed;
  final int remaining;
  final bool skippedNoTransport;
}

/// P04.3 coordinated Outbox drain.
///
/// The coordinator owns serialization, acknowledgement validation, retry/error
/// projection and lifecycle-triggered retries. It never assumes a backend URL:
/// production sync begins only after a real [OutboxSyncTransport] is supplied.
class OutboxSyncCoordinator with WidgetsBindingObserver {
  OutboxSyncCoordinator({
    required SyncStateService status,
    this.sendTimeout = const Duration(seconds: 20),
    this.retryInterval = const Duration(seconds: 30),
  }) : _status = status;

  static final OutboxSyncCoordinator instance = OutboxSyncCoordinator(
    status: SyncStateService.instance,
  );

  final SyncStateService _status;
  final Duration sendTimeout;
  final Duration retryInterval;
  final Lock _drainLock = Lock();

  OutboxSyncTransport? _transport;
  Timer? _retryTimer;
  bool _started = false;

  bool get transportConfigured => _transport != null;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _status.setTransportConfigured(transportConfigured);
    final db = await DBService.database;
    await OfflineOutboxService.resetInterruptedSending(db);
    await _status.start();
    await drain(database: db);
    _retryTimer = Timer.periodic(retryInterval, (_) {
      unawaited(drain());
    });
  }

  void configureTransport(OutboxSyncTransport transport) {
    _transport = transport;
    _status.setTransportConfigured(true);
    unawaited(drain());
  }

  void clearTransport() {
    _transport = null;
    _status.setTransportConfigured(false);
  }

  Future<void> stop() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
    await _status.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(drain());
    }
  }

  Future<OutboxDrainResult> drain({
    DatabaseExecutor? database,
    OutboxSyncTransport? transportOverride,
  }) {
    return _drainLock.synchronized(() async {
      final db = database ?? await DBService.database;
      final transport = transportOverride ?? _transport;
      final configured = transport != null;
      _status.setTransportConfigured(configured);

      if (transport == null) {
        await _status.refresh(database: db);
        final stats = await OfflineOutboxService.queueStats(db);
        return OutboxDrainResult(
          sent: 0,
          failed: 0,
          remaining: stats.unsent,
          skippedNoTransport: true,
        );
      }

      var sent = 0;
      var failed = 0;

      await SyncFoundationService.materializeMissingOutbox(db);
      final ready = await OfflineOutboxService.ready(db: db);
      if (ready.isEmpty) {
        final stats = await OfflineOutboxService.queueStats(db);
        if (stats.unsent == 0) {
          _status.setSynced();
        } else {
          await _status.refresh(database: db);
        }
        return OutboxDrainResult(
          sent: 0,
          failed: 0,
          remaining: stats.unsent,
          skippedNoTransport: false,
        );
      }

      for (final row in ready) {
        final messageId = row['id']?.toString() ?? '';
        if (messageId.isEmpty) {
          failed += 1;
          _status.setFailed('Outbox row has no message id.');
          break;
        }

        try {
          final metadata = await SyncFoundationService.metadataForOutbox(
            db,
            messageId,
          );
          final envelope = OutboxSyncEnvelope.fromRow({
            ...row,
            if (metadata != null) ...metadata,
          });

          await OfflineOutboxService.markSending(db, envelope.id);
          final stats = await OfflineOutboxService.queueStats(db);
          _status.setSyncing(
            pendingCount: stats.pending,
            sendingCount: stats.sending,
          );

          final ack = await transport.send(envelope).timeout(sendTimeout);

          if (!ack.accepted) {
            throw const OutboxSyncProtocolException(
              'Remote endpoint rejected the mutation.',
            );
          }
          if (ack.idempotencyKey != envelope.idempotencyKey) {
            throw const OutboxSyncProtocolException(
              'Acknowledgement idempotency key mismatch.',
            );
          }

          await OfflineOutboxService.markSent(db, envelope.id);
          sent += 1;
        } on SocketException catch (error) {
          await OfflineOutboxService.markFailed(
            db,
            messageId,
            error: error.toString(),
          );
          failed += 1;
          _status.setOffline(error.toString());
          break;
        } on TimeoutException catch (error) {
          await OfflineOutboxService.markFailed(
            db,
            messageId,
            error: error.toString(),
          );
          failed += 1;
          _status.setOffline(error.toString());
          break;
        } on OSError catch (error) {
          await OfflineOutboxService.markFailed(
            db,
            messageId,
            error: error.toString(),
          );
          failed += 1;
          _status.setOffline(error.toString());
          break;
        } catch (error) {
          await OfflineOutboxService.markFailed(
            db,
            messageId,
            error: error.toString(),
          );
          failed += 1;
          _status.setFailed(error.toString());
          break;
        }
      }

      final finalStats = await OfflineOutboxService.queueStats(db);
      if (finalStats.unsent == 0) {
        _status.setSynced();
      } else if (_status.snapshot.phase != YallaSyncPhase.offline &&
          _status.snapshot.phase != YallaSyncPhase.failed) {
        await _status.refresh(database: db);
      }

      return OutboxDrainResult(
        sent: sent,
        failed: failed,
        remaining: finalStats.unsent,
        skippedNoTransport: false,
      );
    });
  }
}
