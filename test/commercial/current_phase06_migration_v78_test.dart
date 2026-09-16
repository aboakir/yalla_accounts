import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v77 to v78 preserves Party data and installs remote sync context',
      () async {
    final dir = await Directory.systemTemp.createTemp('phase06_v78_');
    final path = '${dir.path}/fixture.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      expect(DatabaseConstants.dbVersion, 78);
      expect(await db.getVersion(), 78);
      await db.insert('parties', {
        'id': 'CUSTOMER:900',
        'display_name': 'Preserved Party',
        'is_active': 1,
        'created_at': '2026-09-16T10:00:00.000Z',
      });
      await db.update('party_projection_guard', {'suppressed': 1},
          where: 'singleton_id=1');
      await db.insert('clients', {
        'name': 'Legacy Projection',
        'type': 'أفراد',
        'phone': '',
        'email': '',
        'address': '',
        'notes': '',
      });
      await db.update('party_projection_guard', {'suppressed': 0},
          where: 'singleton_id=1');
      final legacyChange = (await db.query(
        SyncFoundationTables.changes,
        where: "entity_type='client' AND origin='local'",
        orderBy: 'sequence DESC',
        limit: 1,
      ))
          .single;
      await db.insert(UnifiedSyncTables.outbox, {
        'outbox_id': legacyChange['change_id'],
        'change_id': legacyChange['change_id'],
        'organization_id': legacyChange['organization_id'],
        'entity_type': 'client',
        'entity_id': legacyChange['entity_id'],
        'entity_uuid': legacyChange['entity_uuid'],
        'operation': 'UPSERT',
        'base_revision': 0,
        'revision': legacyChange['revision'],
        'idempotency_key': 'sync-change:${legacyChange['change_id']}',
        'occurred_at': legacyChange['occurred_at'],
        'payload_json': legacyChange['after_json'],
        'state': 'PENDING',
        'created_at': legacyChange['occurred_at'],
        'updated_at': legacyChange['occurred_at'],
      });
      await db.delete('schema_migrations', where: 'version=?', whereArgs: [78]);
      final triggers = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE 'trg_party_%' OR name LIKE 'trg_sync_%')",
      );
      for (final row in triggers) {
        final name = row['name']!.toString();
        await db.execute('DROP TRIGGER IF EXISTS "$name"');
      }
      for (final column in [
        'phone',
        'email',
        'address',
        'notes',
        'role_codes'
      ]) {
        await db.execute('ALTER TABLE parties DROP COLUMN $column');
      }
      for (final column in [
        'origin',
        'remote_entity_type',
        'remote_entity_uuid',
        'remote_revision',
      ]) {
        await db.execute(
          'ALTER TABLE ${SyncFoundationTables.context} DROP COLUMN $column',
        );
      }
      await db.setVersion(77);
      await db.close();

      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), 78);
      expect(
        await db
            .query('schema_migrations', where: 'version=?', whereArgs: [78]),
        hasLength(1),
      );
      final legacyOutbox = (await db.query(
        UnifiedSyncTables.outbox,
        where: "entity_type='client'",
      ))
          .single;
      expect(legacyOutbox['state'], 'REJECTED');
      expect(legacyOutbox['last_error'], 'SYNC_SUPERSEDED_BY_MASTER_PARTY');
      final queueStats = await UnifiedSyncQueueService.queueStats(db);
      expect(queueStats.failed, 0);
      final party = (await db.query(
        'parties',
        where: 'id=?',
        whereArgs: ['CUSTOMER:900'],
      ))
          .single;
      expect(party['display_name'], 'Preserved Party');
      expect(party['is_active'], 1);
      final partyColumns = (await db.rawQuery('PRAGMA table_info(parties)'))
          .map((row) => row['name']!.toString())
          .toSet();
      expect(
        partyColumns
            .containsAll(['phone', 'email', 'address', 'notes', 'role_codes']),
        isTrue,
      );
      final contextColumns = (await db.rawQuery(
        'PRAGMA table_info(${SyncFoundationTables.context})',
      ))
          .map((row) => row['name']!.toString())
          .toSet();
      expect(
        contextColumns.containsAll([
          'origin',
          'remote_entity_type',
          'remote_entity_uuid',
          'remote_revision',
        ]),
        isTrue,
      );
      final syncTriggerRows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM sqlite_master WHERE type='trigger' AND name='trg_sync_parties_update'",
      );
      expect((syncTriggerRows.single['c'] as num).toInt(), 1);
    } finally {
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });
}
