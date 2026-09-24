import 'package:sqflite/sqflite.dart';

import '../db/tables/unified_sync_tables.dart';
import 'sync_v3_transport.dart';
import 'unified_sync_queue_service.dart';

class UnifiedSyncBootstrapService {
  UnifiedSyncBootstrapService._();

  static Future<int> runIfRequired(
    Database db, {
    required String organizationId,
    required SyncV3Transport transport,
    required Future<void> Function(
      DatabaseExecutor transaction,
      InboundSyncChange change,
    ) apply,
  }) async {
    if (transport is! SyncV3BootstrapTransport) return 0;
    final bootstrapTransport = transport as SyncV3BootstrapTransport;
    final rows = await db.query(
      UnifiedSyncTables.bootstrapState,
      where: 'organization_id=?',
      whereArgs: [organizationId],
      limit: 1,
    );
    if (rows.isNotEmpty && rows.single['state'] == 'READY') return 0;
    final checkpoint =
        await UnifiedSyncQueueService.checkpointFor(db, organizationId);
    if (rows.isEmpty && checkpoint > 0) return 0;

    int cursor = rows.isEmpty
        ? 0
        : (rows.single['cursor_server_sequence'] as num).toInt();
    int? snapshot = rows.isEmpty
        ? null
        : (rows.single['snapshot_server_sequence'] as num).toInt();
    var appliedCount = 0;

    for (var page = 0; page < 1000; page++) {
      final response = await bootstrapTransport.bootstrap(
        cursorServerSequence: cursor,
        snapshotServerSequence: snapshot,
      );
      snapshot ??= response.snapshotSequence;
      if (response.snapshotSequence != snapshot ||
          response.cursorSequence != cursor ||
          response.nextCursorSequence < cursor ||
          (response.hasMore && response.nextCursorSequence == cursor)) {
        throw const SyncV3TransportException(
          'Bootstrap snapshot cursor mismatch.',
        );
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
          organizationId: organizationId,
          changes: inbound,
          apply: apply,
        );
        appliedCount += inbound.length;
      }
      cursor = response.nextCursorSequence;
      await db.insert(
        UnifiedSyncTables.bootstrapState,
        {
          'organization_id': organizationId,
          'state': 'IN_PROGRESS',
          'snapshot_server_sequence': snapshot,
          'cursor_server_sequence': cursor,
          'updated_at': _now(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (!response.hasMore) {
        await db.transaction((txn) async {
          await txn.insert(
            UnifiedSyncTables.checkpoint,
            {
              'organization_id': organizationId,
              'last_server_sequence': snapshot,
              'updated_at': _now(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await txn.insert(
            UnifiedSyncTables.bootstrapState,
            {
              'organization_id': organizationId,
              'state': 'READY',
              'snapshot_server_sequence': snapshot,
              'cursor_server_sequence': snapshot,
              'updated_at': _now(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });
        return appliedCount;
      }
    }
    throw const SyncV3TransportException('Bootstrap page limit exceeded.');
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
}
