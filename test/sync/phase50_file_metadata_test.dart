import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_file_metadata_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_inbound_router.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';

const org = '22222222-2222-4222-8222-222222222222';
const repairUuid = '11111111-1111-4111-8111-111111111111';

Future<Database> _db(String path, String device) async {
  final db = await databaseFactoryFfi.openDatabase(path);
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
  await db.insert('installation_identity', {
    'singleton_id': 1,
    'organization_id': org,
    'device_id': device,
  });
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
  await SyncFoundationTables.ensure(db);
  await UnifiedSyncTables.ensure(db);
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(SyncFoundationTables.registry, {
    'entity_uuid': repairUuid,
    'entity_type': 'repair',
    'local_id': 'R-1',
    'organization_id': org,
    'revision': 1,
    'is_voided': 0,
    'snapshot_json': '{}',
    'financial_json': '{}',
    'created_at': now,
    'updated_at': now,
  });
  return db;
}

InboundSyncChange _wire(
  Map<String, Object?> outbox,
  int serverSequence,
) {
  return InboundSyncChange(
    serverSequence: serverSequence,
    changeId: outbox['change_id']!.toString(),
    entityType: outbox['entity_type']!.toString(),
    entityId: outbox['entity_id']!.toString(),
    entityUuid: outbox['entity_uuid']!.toString(),
    operation: outbox['operation']!.toString(),
    revision: (outbox['revision'] as num).toInt(),
    occurredAt: DateTime.parse(outbox['occurred_at']!.toString()),
    payload: Map<String, Object?>.from(
      jsonDecode(outbox['payload_json']!.toString()) as Map,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
      'phase50 metadata syncs path/hash/id without file blob or blocking binary',
      () async {
    final rootA = await Directory.systemTemp.createTemp('phase50_files_a_');
    final rootB = await Directory.systemTemp.createTemp('phase50_files_b_');
    final dbA = await _db(
      '${rootA.path}/a.db',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final dbB = await _db(
      '${rootB.path}/b.db',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    try {
      YallaStorageService.useRootDirectoryForTesting(rootA);
      final image = File('${rootA.path}/repairs/test.jpg');
      await image.parent.create(recursive: true);
      final bytes = List<int>.generate(512, (i) => i % 251);
      await image.writeAsBytes(bytes);
      const storedPath = 'repairs/test.jpg';

      await SyncFileMetadataService.registerStoredFile(
        dbA,
        entityType: 'repair',
        localEntityId: 'R-1',
        storedPath: storedPath,
        mimeType: 'image/jpeg',
      );
      final rowA = (await dbA.query(UnifiedSyncTables.fileRefs)).single;
      expect(rowA['stored_path'], storedPath);
      expect(rowA['entity_uuid'], repairUuid);
      expect(rowA['sha256'], sha256.convert(bytes).toString());
      expect(rowA['size_bytes'], bytes.length);
      expect(rowA.keys, isNot(contains('bytes')));

      final pendingA = await UnifiedSyncQueueService.pendingOutbox(dbA);
      expect(pendingA, hasLength(1));
      expect(pendingA.single['entity_type'], 'file_ref');
      expect(pendingA.single['operation'], 'UPSERT');
      final payload =
          jsonDecode(pendingA.single['payload_json']!.toString()) as Map;
      expect(payload['file_id'], rowA['file_id']);
      expect(payload['parent_entity_uuid'], repairUuid);
      expect(payload['sha256'], sha256.convert(bytes).toString());
      expect(payload.containsKey('bytes'), isFalse);

      YallaStorageService.useRootDirectoryForTesting(rootB);
      expect(
        await YallaStorageService.resolveFile(storedPath),
        anyOf(isNull, isA<File>()),
      );
      final inbound = _wire(pendingA.single, 1);
      await UnifiedSyncQueueService.applyInboundBatch(
        dbB,
        organizationId: org,
        changes: [inbound],
        apply: UnifiedSyncInboundRouter.apply,
      );
      final rowB = (await dbB.query(UnifiedSyncTables.fileRefs)).single;
      expect(rowB['file_id'], rowA['file_id']);
      expect(rowB['stored_path'], storedPath);
      expect(rowB['sha256'], rowA['sha256']);
      final binaryOnB = await YallaStorageService.resolveFile(storedPath);
      expect(binaryOnB == null || !await binaryOnB.exists(), isTrue);

      await SyncFileMetadataService.removeByPath(dbA, storedPath);
      expect(await dbA.query(UnifiedSyncTables.fileRefs), isEmpty);
      final allOutbox = await dbA.query(
        UnifiedSyncTables.outbox,
        orderBy: 'created_at ASC',
      );
      expect(allOutbox, hasLength(2));
      expect(allOutbox.last['entity_type'], 'file_ref');
      expect(allOutbox.last['operation'], 'DELETE');

      await UnifiedSyncQueueService.applyInboundBatch(
        dbB,
        organizationId: org,
        changes: [_wire(Map<String, Object?>.from(allOutbox.last), 2)],
        apply: UnifiedSyncInboundRouter.apply,
      );
      expect(await dbB.query(UnifiedSyncTables.fileRefs), isEmpty);
    } finally {
      await dbA.close();
      await dbB.close();
      YallaStorageService.useRootDirectoryForTesting(null);
      await rootA.delete(recursive: true);
      await rootB.delete(recursive: true);
    }
  });
}
