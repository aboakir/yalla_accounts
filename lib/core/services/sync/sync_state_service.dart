import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db_service.dart';
import '../offline_outbox_service.dart';
import 'unified_sync_queue_service.dart';

enum YallaSyncPhase {
  checking,
  localOnly,
  pending,
  syncing,
  synced,
  offline,
  failed,
}

class YallaSyncSnapshot {
  const YallaSyncSnapshot({
    required this.phase,
    required this.pendingCount,
    required this.failedCount,
    required this.sendingCount,
    required this.transportConfigured,
    this.lastSyncedAt,
    this.lastError,
  });

  const YallaSyncSnapshot.checking()
      : phase = YallaSyncPhase.checking,
        pendingCount = 0,
        failedCount = 0,
        sendingCount = 0,
        transportConfigured = false,
        lastSyncedAt = null,
        lastError = null;

  final YallaSyncPhase phase;
  final int pendingCount;
  final int failedCount;
  final int sendingCount;
  final bool transportConfigured;
  final DateTime? lastSyncedAt;
  final String? lastError;

  YallaSyncSnapshot copyWith({
    YallaSyncPhase? phase,
    int? pendingCount,
    int? failedCount,
    int? sendingCount,
    bool? transportConfigured,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return YallaSyncSnapshot(
      phase: phase ?? this.phase,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      sendingCount: sendingCount ?? this.sendingCount,
      transportConfigured: transportConfigured ?? this.transportConfigured,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Single source of truth for the visible sync indicator.
class SyncStateService {
  SyncStateService({
    this.pollInterval = const Duration(seconds: 15),
  });

  static final SyncStateService instance = SyncStateService();

  final Duration pollInterval;
  final ValueNotifier<YallaSyncSnapshot> _notifier =
      ValueNotifier<YallaSyncSnapshot>(
    const YallaSyncSnapshot.checking(),
  );

  StreamSubscription<void>? _outboxSubscription;
  Timer? _timer;
  bool _started = false;
  bool _transportConfigured = false;

  ValueListenable<YallaSyncSnapshot> get listenable => _notifier;
  YallaSyncSnapshot get snapshot => _notifier.value;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _outboxSubscription = OfflineOutboxService.changes.listen((_) {
      unawaited(refresh());
    });

    await refresh();

    _timer = Timer.periodic(pollInterval, (_) {
      unawaited(refresh());
    });
  }

  void setTransportConfigured(bool configured) {
    _transportConfigured = configured;
    if (_started) {
      unawaited(refresh());
    }
  }

  Future<void> refresh({DatabaseExecutor? database}) async {
    try {
      final db = database ?? await DBService.database;
      final stats = await UnifiedSyncQueueService.queueStats(db);
      final current = _notifier.value;

      final phase = current.phase == YallaSyncPhase.syncing && stats.sending > 0
          ? YallaSyncPhase.syncing
          : !_transportConfigured
              ? YallaSyncPhase.localOnly
              : stats.unsent > 0
                  ? YallaSyncPhase.pending
                  : YallaSyncPhase.synced;

      _notifier.value = current.copyWith(
        phase: phase,
        pendingCount: stats.pending,
        failedCount: stats.failed,
        sendingCount: stats.sending,
        transportConfigured: _transportConfigured,
        clearError:
            phase != YallaSyncPhase.failed && phase != YallaSyncPhase.offline,
      );
    } catch (error) {
      setFailed(error.toString());
    }
  }

  void setSyncing({
    required int pendingCount,
    required int sendingCount,
  }) {
    _notifier.value = _notifier.value.copyWith(
      phase: YallaSyncPhase.syncing,
      pendingCount: pendingCount,
      sendingCount: sendingCount,
      transportConfigured: true,
      clearError: true,
    );
  }

  void setLocalOnly({
    required int pendingCount,
    required int failedCount,
    required int sendingCount,
  }) {
    _transportConfigured = false;
    _notifier.value = _notifier.value.copyWith(
      phase: YallaSyncPhase.localOnly,
      pendingCount: pendingCount,
      failedCount: failedCount,
      sendingCount: sendingCount,
      transportConfigured: false,
      clearError: true,
    );
  }

  void setOffline(String error) {
    _notifier.value = _notifier.value.copyWith(
      phase: YallaSyncPhase.offline,
      transportConfigured: true,
      lastError: error,
    );
  }

  void setFailed(String error) {
    _notifier.value = _notifier.value.copyWith(
      phase: YallaSyncPhase.failed,
      lastError: error,
    );
  }

  void setSynced() {
    _notifier.value = _notifier.value.copyWith(
      phase: YallaSyncPhase.synced,
      pendingCount: 0,
      failedCount: 0,
      sendingCount: 0,
      transportConfigured: true,
      lastSyncedAt: DateTime.now().toUtc(),
      clearError: true,
    );
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _outboxSubscription?.cancel();
    _outboxSubscription = null;
    _started = false;
  }
}
