import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../current_user_context.dart';
import '../db/tables/sync_foundation_tables.dart';
import '../offline_outbox_service.dart';

enum SyncChangeOperation { created, updated, voided, restored }

/// A proposed remote version, never an instruction to apply financial data.
class RemoteSyncCandidate {
  const RemoteSyncCandidate({
    required this.changeId,
    required this.organizationId,
    required this.deviceId,
    required this.userId,
    required this.entityUuid,
    required this.entityType,
    required this.baseRevision,
    required this.operation,
    required this.occurredAt,
    required this.snapshot,
  });

  final String changeId;
  final String organizationId;
  final String deviceId;
  final String userId;
  final String entityUuid;
  final String entityType;
  final int baseRevision;
  final SyncChangeOperation operation;
  final DateTime occurredAt;
  final Map<String, Object?> snapshot;

  Map<String, Object?> toJson() => {
        'change_id': changeId,
        'organization_id': organizationId,
        'device_id': deviceId,
        'user_id': userId,
        'entity_uuid': entityUuid,
        'entity_type': entityType,
        'base_revision': baseRevision,
        'operation': operation.name,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'snapshot': snapshot,
      };
}

class SyncCandidateReview {
  const SyncCandidateReview({
    required this.candidateId,
    required this.reasons,
    required this.duplicate,
  });
  final String candidateId;
  final List<String> reasons;
  final bool duplicate;
  bool get hasConflict => reasons.isNotEmpty;
  bool get requiresReview => true;
  bool get applied => false;
}

/// Local capture and quarantine only. This class has no transport or apply API.
/// Posting, balances, document creation and reversals remain with their existing
/// single-source services and database guards.
class SyncFoundationService {
  SyncFoundationService._();

  static bool get remoteFinancialSyncEnabled => false;

  static Future<T> transaction<T>(
    Database db,
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) =>
      db.transaction((txn) => withCurrentActor(txn, () => action(txn)),
          exclusive: exclusive);

  /// Attribute an existing write using its caller's executor. Autocommit calls
  /// get a transaction; existing transactions are reused, never nested.
  static Future<T> writeOn<T>(DatabaseExecutor executor,
      Future<T> Function(DatabaseExecutor txn) action) {
    if (executor is Database) {
      return transaction(executor, (txn) => action(txn));
    }
    return withCurrentActor(executor, () => action(executor));
  }

  /// Context exists only within this SQLite transaction and is restored even
  /// when an action fails. It never caches a login or queries a different DB.
  /// Older focused schemas keep working before Stage 50 has been installed.
  static Future<T> withCurrentActor<T>(
    DatabaseExecutor executor,
    Future<T> Function() action,
  ) async {
    if (executor is! Transaction) {
      throw ArgumentError('Sync actor context requires a SQLite transaction.');
    }
    if (!await SyncFoundationTables.isInstalled(executor)) return action();
    final old = await executor.query(SyncFoundationTables.context,
        where: 'singleton_id=1', limit: 1);
    final userId = await CurrentUserContext.userId();
    await executor.insert(
        SyncFoundationTables.context, {'singleton_id': 1, 'user_id': userId},
        conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      return await action();
    } finally {
      if (old.isEmpty) {
        await executor.delete(SyncFoundationTables.context,
            where: 'singleton_id=1');
      } else {
        await executor.update(
            SyncFoundationTables.context, {'user_id': old.single['user_id']},
            where: 'singleton_id=1');
      }
    }
  }

  static Future<Map<String, Object?>?> identityFor(
    DatabaseExecutor db, {
    required String entityType,
    required String localId,
  }) async {
    final rows = await db.query(SyncFoundationTables.registry,
        where: 'entity_type=? AND local_id=?',
        whereArgs: [entityType, localId],
        limit: 1);
    return rows.isEmpty ? null : rows.single;
  }

  /// Resolve the immutable local change linked to one durable outbox row.
  /// The wire layer uses this metadata; it never reconstructs a financial
  /// mutation from the current document after the queued revision has changed.
  static Future<Map<String, Object?>?> metadataForOutbox(
    DatabaseExecutor db,
    String outboxId,
  ) async {
    if (!await SyncFoundationTables.isInstalled(db)) return null;
    final rows = await db.rawQuery('''
      SELECT c.change_id AS sync_change_id,
             c.entity_uuid AS sync_entity_uuid,
             c.revision AS sync_revision,
             c.operation AS sync_change_operation,
             c.occurred_at AS sync_occurred_at,
             c.user_id AS sync_user_id,
             COALESCE(c.after_json,c.before_json,'{}') AS sync_snapshot_json
      FROM ${SyncFoundationTables.outboxLinks} l
      JOIN ${SyncFoundationTables.changes} c ON c.change_id=l.change_id
      WHERE l.outbox_id=? LIMIT 1
    ''', [outboxId]);
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  /// Materialize captured local changes that lack a feature-specific outbox.
  static Future<int> materializeMissingOutbox(DatabaseExecutor db,
      {int limit = 200}) async {
    if (!await SyncFoundationTables.isInstalled(db)) return 0;
    final missing = await db.rawQuery('''
      SELECT c.change_id,c.entity_type,c.entity_id,c.entity_uuid,c.revision,c.operation
      FROM ${SyncFoundationTables.changes} c
      LEFT JOIN ${SyncFoundationTables.outboxLinks} l ON l.change_id=c.change_id
      WHERE c.origin='local' AND l.outbox_id IS NULL
      ORDER BY c.sequence ASC LIMIT ?
    ''', [limit]);
    var created = 0;
    for (final row in missing) {
      final changeId = row['change_id']!.toString();
      final inserted = await OfflineOutboxService.enqueue(
        db,
        channel: OfflineOutboxService.channelSync,
        operation: row['operation'] == 'voided' ? 'DELETE' : 'UPSERT',
        entityType: row['entity_type']!.toString(),
        entityId: row['entity_id']!.toString(),
        idempotencyKey: 'sync-change:$changeId',
        payload: <String, dynamic>{
          'schema': 2,
          'change_id': changeId,
          'entity_uuid': row['entity_uuid']!.toString(),
          'revision': row['revision'],
        },
      );
      if (inserted) created += 1;
    }
    return created;
  }

  /// Persist the proposal and conflict evidence in one transaction. A matching
  /// retry returns the same candidate; reuse of its id for a different payload
  /// is rejected. Even a conflict-free proposal awaits a future reviewed flow.
  static Future<SyncCandidateReview> quarantineCandidate(
    Database db,
    RemoteSyncCandidate candidate,
  ) async {
    for (final entry in {
      'changeId': candidate.changeId,
      'organizationId': candidate.organizationId,
      'deviceId': candidate.deviceId,
      'userId': candidate.userId,
      'entityUuid': candidate.entityUuid,
      'entityType': candidate.entityType,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw ArgumentError.value(entry.value, entry.key, 'must not be blank');
      }
    }
    if (candidate.baseRevision < 0) {
      throw ArgumentError.value(candidate.baseRevision, 'baseRevision');
    }
    final payload = _canonical(candidate.toJson());
    final digest = sha256.convert(utf8.encode(payload)).toString();
    return db.transaction((txn) async {
      final prior = await txn.query(SyncFoundationTables.candidates,
          where: 'organization_id=? AND remote_change_id=?',
          whereArgs: [candidate.organizationId, candidate.changeId],
          limit: 1);
      if (prior.isNotEmpty) {
        if (prior.single['payload_sha256'] != digest) {
          throw StateError('SYNC_REMOTE_IDEMPOTENCY_PAYLOAD_MISMATCH');
        }
        final id = prior.single['candidate_id'] as String;
        final conflicts = await txn.query(SyncFoundationTables.conflicts,
            where: 'candidate_id=?', whereArgs: [id], limit: 1);
        return SyncCandidateReview(
            candidateId: id,
            duplicate: true,
            reasons: conflicts.isEmpty
                ? const []
                : List<String>.from(
                    jsonDecode(conflicts.single['reasons_json'] as String)
                        as List));
      }
      final local = await txn.query(SyncFoundationTables.registry,
          where: 'entity_uuid=?', whereArgs: [candidate.entityUuid], limit: 1);
      final reasons = <String>[];
      int? localRevision;
      String? localSnapshot;
      if (local.isEmpty) {
        reasons.add('unknown_entity');
      } else {
        final row = local.single;
        localRevision = row['revision'] as int;
        localSnapshot = row['snapshot_json'] as String;
        if (row['organization_id'] == null) {
          reasons.add('local_identity_unavailable');
        } else if (row['organization_id'] != candidate.organizationId) {
          reasons.add('organization_scope_mismatch');
        }
        if (row['entity_type'] != candidate.entityType) {
          reasons.add('entity_type_mismatch');
        }
        final localVoided = row['is_voided'] == 1;
        final remoteVoided = candidate.operation == SyncChangeOperation.voided;
        if (localRevision != candidate.baseRevision) {
          reasons.add('concurrent_update');
          if (localVoided != remoteVoided) reasons.add('delete_vs_update');
        } else if (localVoided &&
            !remoteVoided &&
            candidate.operation != SyncChangeOperation.restored) {
          reasons.add('explicit_restore_required');
        }
        final financial = Map<String, Object?>.from(
            jsonDecode(row['financial_json'] as String) as Map);
        if (financial.keys.any((k) => !candidate.snapshot.containsKey(k))) {
          reasons.add('incomplete_financial_snapshot');
        } else if (_canonical(financial) !=
            _canonical({
              for (final key in financial.keys) key: candidate.snapshot[key],
            })) {
          reasons.add('financial_value_difference');
        }
        final state =
            Map<String, Object?>.from(jsonDecode(localSnapshot) as Map);
        if (candidate.entityType.startsWith('gl_') ||
            state['is_posted'] == 1 ||
            state['post_to_gl'] == 1 ||
            state['gl_entry_id'] != null) {
          if (_canonical(state) != _canonical(candidate.snapshot) ||
              remoteVoided) {
            reasons.add('posted_document_requires_existing_reversal_flow');
          }
        }
      }
      final id = const Uuid().v4();
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.insert(SyncFoundationTables.candidates, {
        'candidate_id': id,
        'organization_id': candidate.organizationId,
        'remote_change_id': candidate.changeId,
        'entity_uuid': candidate.entityUuid,
        'payload_sha256': digest,
        'payload_json': payload,
        'received_at': now,
        'disposition': reasons.isEmpty ? 'requires_review' : 'conflict',
      });
      if (reasons.isNotEmpty) {
        await txn.insert(SyncFoundationTables.conflicts, {
          'conflict_id': const Uuid().v4(),
          'candidate_id': id,
          'entity_uuid': candidate.entityUuid,
          'local_revision': localRevision,
          'remote_base_revision': candidate.baseRevision,
          'reasons_json': jsonEncode(reasons),
          'local_snapshot_json': localSnapshot,
          'remote_snapshot_json': _canonical(candidate.snapshot),
          'detected_at': now,
          'status': 'open',
        });
      }
      return SyncCandidateReview(
          candidateId: id,
          reasons: List.unmodifiable(reasons),
          duplicate: false);
    });
  }

  static String _canonical(Object? value) {
    Object? sort(Object? node) {
      if (node is Map) {
        final keys = node.keys.map((k) => k.toString()).toList()..sort();
        return {for (final key in keys) key: sort(node[key])};
      }
      if (node is List) return node.map(sort).toList();
      // JSON's 10 and 10.0 carry the same financial value.
      if (node is num && node.isFinite && node == node.roundToDouble()) {
        return node.toInt();
      }
      return node;
    }

    return jsonEncode(sort(value));
  }
}
