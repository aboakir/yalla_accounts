import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../storage/yalla_storage_service.dart';
import '../db/tables/sync_foundation_tables.dart';
import '../db/tables/unified_sync_tables.dart';
import 'unified_sync_queue_service.dart';

class SyncFileMetadataService {
  SyncFileMetadataService._();

  static Future<void> registerStoredFile(
    DatabaseExecutor db, {
    required String entityType,
    required String localEntityId,
    required String storedPath,
    String? mimeType,
  }) async {
    final registry = await db.query(
      SyncFoundationTables.registry,
      columns: const ['organization_id', 'entity_uuid'],
      where: 'entity_type=? AND local_id=?',
      whereArgs: [entityType, localEntityId],
      limit: 1,
    );
    if (registry.isEmpty) return;
    final file = await YallaStorageService.resolveFile(storedPath);
    if (file == null || !await file.exists()) return;
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    final parent = registry.single;
    Future<void> action(DatabaseExecutor txn) => _register(
          txn,
          organizationId: parent['organization_id']!.toString(),
          parentEntityType: entityType,
          parentEntityUuid: parent['entity_uuid']!.toString(),
          storedPath: storedPath,
          sha256Hex: hash,
          sizeBytes: bytes.length,
          mimeType: mimeType,
        );
    if (db is Database) {
      await db.transaction(action);
    } else {
      await action(db);
    }
  }

  static Future<void> _register(
    DatabaseExecutor db, {
    required String organizationId,
    required String parentEntityType,
    required String parentEntityUuid,
    required String storedPath,
    required String sha256Hex,
    required int sizeBytes,
    required String? mimeType,
  }) async {
    final existing = await db.query(
      UnifiedSyncTables.fileRefs,
      where:
          'organization_id=? AND entity_type=? AND entity_uuid=? AND stored_path=?',
      whereArgs: [
        organizationId,
        parentEntityType,
        parentEntityUuid,
        storedPath,
      ],
      limit: 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final fileId = existing.isEmpty
        ? const Uuid().v4()
        : existing.single['file_id']!.toString();
    final payload = <String, Object?>{
      'file_id': fileId,
      'parent_entity_type': parentEntityType,
      'parent_entity_uuid': parentEntityUuid,
      'stored_path': storedPath,
      'sha256': sha256Hex,
      'size_bytes': sizeBytes,
      'mime_type': mimeType,
    };
    final snapshot = _canonical(payload);
    Map<String, Object?>? identity;
    if (existing.isNotEmpty) {
      final rows = await db.query(
        SyncFoundationTables.registry,
        where: 'entity_uuid=? AND entity_type=?',
        whereArgs: [fileId, 'file_ref'],
        limit: 1,
      );
      if (rows.isNotEmpty) identity = rows.single;
      final unchanged = existing.single['sha256'] == sha256Hex &&
          existing.single['size_bytes'] == sizeBytes &&
          existing.single['mime_type'] == mimeType;
      if (unchanged && identity != null && identity['is_voided'] == 0) return;
    }

    final previousSnapshot = identity?['snapshot_json']?.toString();
    final revision = identity == null
        ? 1
        : ((identity['revision'] as num?)?.toInt() ?? 0) + 1;
    final createdAt =
        existing.isEmpty ? now : existing.single['created_at']!.toString();

    if (existing.isEmpty) {
      await db.insert(UnifiedSyncTables.fileRefs, {
        'file_id': fileId,
        'organization_id': organizationId,
        'entity_type': parentEntityType,
        'entity_uuid': parentEntityUuid,
        'stored_path': storedPath,
        'sha256': sha256Hex,
        'size_bytes': sizeBytes,
        'mime_type': mimeType,
        'created_at': createdAt,
        'updated_at': now,
      });
    } else {
      await db.update(
        UnifiedSyncTables.fileRefs,
        {
          'sha256': sha256Hex,
          'size_bytes': sizeBytes,
          'mime_type': mimeType,
          'updated_at': now,
        },
        where: 'file_id=?',
        whereArgs: [fileId],
      );
    }

    if (identity == null) {
      await db.insert(SyncFoundationTables.registry, {
        'entity_uuid': fileId,
        'entity_type': 'file_ref',
        'local_id': fileId,
        'organization_id': organizationId,
        'revision': revision,
        'is_voided': 0,
        'snapshot_json': snapshot,
        'financial_json': '{}',
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await db.update(
        SyncFoundationTables.registry,
        {
          'revision': revision,
          'is_voided': 0,
          'snapshot_json': snapshot,
          'updated_at': now,
        },
        where: 'entity_uuid=?',
        whereArgs: [fileId],
      );
    }
    await _appendChange(
      db,
      fileId: fileId,
      organizationId: organizationId,
      revision: revision,
      operation: identity == null ? 'created' : 'updated',
      beforeJson: previousSnapshot,
      afterJson: snapshot,
      occurredAt: now,
    );
  }

  static Future<void> removeByPath(
    DatabaseExecutor db,
    String storedPath,
  ) async {
    Future<void> action(DatabaseExecutor txn) async {
      final rows = await txn.query(
        UnifiedSyncTables.fileRefs,
        where: 'stored_path=?',
        whereArgs: [storedPath],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.single;
      final fileId = row['file_id']!.toString();
      final identities = await txn.query(
        SyncFoundationTables.registry,
        where: 'entity_uuid=? AND entity_type=?',
        whereArgs: [fileId, 'file_ref'],
        limit: 1,
      );
      if (identities.isEmpty) {
        await txn.delete(
          UnifiedSyncTables.fileRefs,
          where: 'file_id=?',
          whereArgs: [fileId],
        );
        return;
      }
      final identity = identities.single;
      final revision = ((identity['revision'] as num?)?.toInt() ?? 0) + 1;
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.delete(
        UnifiedSyncTables.fileRefs,
        where: 'file_id=?',
        whereArgs: [fileId],
      );
      await txn.update(
        SyncFoundationTables.registry,
        {'revision': revision, 'is_voided': 1, 'updated_at': now},
        where: 'entity_uuid=?',
        whereArgs: [fileId],
      );
      await _appendChange(
        txn,
        fileId: fileId,
        organizationId: identity['organization_id']!.toString(),
        revision: revision,
        operation: 'voided',
        beforeJson: identity['snapshot_json']!.toString(),
        afterJson: null,
        occurredAt: now,
      );
    }

    if (db is Database) {
      await db.transaction(action);
    } else {
      await action(db);
    }
  }

  static Future<void> applyInbound(
    DatabaseExecutor db,
    InboundSyncChange change,
  ) async {
    if (change.entityType != 'file_ref') {
      throw ArgumentError.value(change.entityType, 'entityType');
    }
    final fileId = change.payload['file_id']?.toString() ?? change.entityUuid;
    if (fileId != change.entityUuid) {
      throw StateError('SYNC_FILE_IDENTITY_MISMATCH');
    }
    final organizationId = await _organizationId(db);
    if (change.operation == 'DELETE') {
      await db.delete(
        UnifiedSyncTables.fileRefs,
        where: 'file_id=?',
        whereArgs: [fileId],
      );
      await _upsertRemoteRegistry(
        db,
        change,
        organizationId: organizationId,
        isVoided: true,
      );
      return;
    }
    final parentType = change.payload['parent_entity_type']?.toString() ?? '';
    final parentUuid = change.payload['parent_entity_uuid']?.toString() ?? '';
    final storedPath = change.payload['stored_path']?.toString() ?? '';
    final hash = change.payload['sha256']?.toString() ?? '';
    final size = (change.payload['size_bytes'] as num?)?.toInt() ?? -1;
    if (parentType.isEmpty ||
        parentUuid.length != 36 ||
        storedPath.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        size < 0) {
      throw StateError('SYNC_FILE_METADATA_INVALID');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final prior = await db.query(
      UnifiedSyncTables.fileRefs,
      columns: const ['created_at'],
      where: 'file_id=?',
      whereArgs: [fileId],
      limit: 1,
    );
    final values = <String, Object?>{
      'file_id': fileId,
      'organization_id': organizationId,
      'entity_type': parentType,
      'entity_uuid': parentUuid,
      'stored_path': storedPath,
      'sha256': hash,
      'size_bytes': size,
      'mime_type': change.payload['mime_type']?.toString(),
      'created_at': prior.isEmpty ? now : prior.single['created_at'],
      'updated_at': now,
    };
    if (prior.isEmpty) {
      await db.insert(UnifiedSyncTables.fileRefs, values);
    } else {
      values.remove('file_id');
      values.remove('created_at');
      await db.update(
        UnifiedSyncTables.fileRefs,
        values,
        where: 'file_id=?',
        whereArgs: [fileId],
      );
    }
    await _upsertRemoteRegistry(
      db,
      change,
      organizationId: organizationId,
      isVoided: false,
    );
  }

  static Future<void> _upsertRemoteRegistry(
    DatabaseExecutor db,
    InboundSyncChange change, {
    required String organizationId,
    required bool isVoided,
  }) async {
    final rows = await db.query(
      SyncFoundationTables.registry,
      where: 'entity_uuid=?',
      whereArgs: [change.entityUuid],
      limit: 1,
    );
    final snapshot = _canonical(change.payload);
    final now = DateTime.now().toUtc().toIso8601String();
    if (rows.isEmpty) {
      await db.insert(SyncFoundationTables.registry, {
        'entity_uuid': change.entityUuid,
        'entity_type': 'file_ref',
        'local_id': change.entityUuid,
        'organization_id': organizationId,
        'revision': change.revision,
        'is_voided': isVoided ? 1 : 0,
        'snapshot_json': snapshot,
        'financial_json': '{}',
        'created_at': now,
        'updated_at': now,
      });
      return;
    }
    await db.update(
      SyncFoundationTables.registry,
      {
        'revision': change.revision,
        'is_voided': isVoided ? 1 : 0,
        'snapshot_json': snapshot,
        'updated_at': now,
      },
      where: 'entity_uuid=? AND entity_type=?',
      whereArgs: [change.entityUuid, 'file_ref'],
    );
  }

  static Future<void> _appendChange(
    DatabaseExecutor db, {
    required String fileId,
    required String organizationId,
    required int revision,
    required String operation,
    required String? beforeJson,
    required String? afterJson,
    required String occurredAt,
  }) async {
    String? deviceId;
    final installation = await db.query(
      'installation_identity',
      columns: const ['device_id'],
      where: 'organization_id=?',
      whereArgs: [organizationId],
      limit: 1,
    );
    if (installation.isNotEmpty) {
      deviceId = installation.single['device_id']?.toString();
    }
    final changeId = const Uuid().v4();
    await db.insert(SyncFoundationTables.changes, {
      'change_id': changeId,
      'entity_uuid': fileId,
      'entity_type': 'file_ref',
      'entity_id': fileId,
      'organization_id': organizationId,
      'device_id': deviceId,
      'user_id': null,
      'occurred_at': occurredAt,
      'operation': operation,
      'revision': revision,
      'before_json': beforeJson,
      'after_json': afterJson,
      'attribution_state': 'unavailable',
      'origin': 'local',
      'idempotency_key': 'file-ref:$fileId:$revision',
    });
  }

  static Future<String> _organizationId(DatabaseExecutor db) async {
    final rows = await db.query(
      'organization_identity',
      columns: const ['organization_id'],
      where: 'singleton_id=1',
      limit: 1,
    );
    final value =
        rows.isEmpty ? '' : rows.single['organization_id']?.toString() ?? '';
    if (value.isEmpty) throw StateError('SYNC_ORGANIZATION_IDENTITY_MISSING');
    return value;
  }

  static String _canonical(Map<String, Object?> value) {
    final keys = value.keys.toList()..sort();
    return jsonEncode({for (final key in keys) key: value[key]});
  }
}
