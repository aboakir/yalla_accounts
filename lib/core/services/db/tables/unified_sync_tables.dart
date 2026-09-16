import 'package:sqflite/sqflite.dart';

import 'sync_foundation_tables.dart';

/// Phase 05 canonical v3 transport queues.
/// Legacy outbox_messages remains readable for v2 compatibility only.
class UnifiedSyncTables {
  UnifiedSyncTables._();

  static const outbox = 'sync_outbox';
  static const inbox = 'sync_inbox';
  static const checkpoint = 'sync_checkpoint';

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $outbox (
      outbox_id TEXT PRIMARY KEY NOT NULL,
      change_id TEXT NOT NULL UNIQUE REFERENCES ${SyncFoundationTables.changes}(change_id),
      organization_id TEXT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      entity_uuid TEXT NOT NULL,
      operation TEXT NOT NULL CHECK(operation IN ('UPSERT','DELETE')),
      base_revision INTEGER NOT NULL CHECK(base_revision >= 0),
      revision INTEGER NOT NULL CHECK(revision = base_revision + 1),
      idempotency_key TEXT NOT NULL UNIQUE,
      occurred_at TEXT NOT NULL,
      payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
      state TEXT NOT NULL DEFAULT 'PENDING' CHECK(state IN
        ('PENDING','SENDING','ACKNOWLEDGED','CONFLICT','REJECTED')),
      attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count >= 0),
      next_attempt_at TEXT,
      last_error TEXT,
      server_sequence INTEGER,
      remote_conflict_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_sync_outbox_ready
      ON $outbox(state,next_attempt_at,created_at)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $inbox (
      inbox_id TEXT PRIMARY KEY NOT NULL,
      organization_id TEXT NOT NULL,
      server_sequence INTEGER NOT NULL CHECK(server_sequence > 0),
      change_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      entity_uuid TEXT NOT NULL,
      operation TEXT NOT NULL CHECK(operation IN ('UPSERT','DELETE')),
      revision INTEGER NOT NULL CHECK(revision > 0),
      occurred_at TEXT NOT NULL,
      payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
      received_at TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'RECEIVED' CHECK(state IN
        ('RECEIVED','APPLIED','CONFLICT','REJECTED')),
      UNIQUE(organization_id,server_sequence),
      UNIQUE(organization_id,change_id)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_sync_inbox_pending
      ON $inbox(organization_id,state,server_sequence)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $checkpoint (
      organization_id TEXT PRIMARY KEY NOT NULL,
      last_server_sequence INTEGER NOT NULL CHECK(last_server_sequence >= 0),
      updated_at TEXT NOT NULL
    )''');

    await db.execute('DROP TRIGGER IF EXISTS trg_sync_v3_change_to_outbox');
    await db.execute('''CREATE TRIGGER trg_sync_v3_change_to_outbox
      AFTER INSERT ON ${SyncFoundationTables.changes}
      WHEN NEW.origin='local' AND NEW.operation IN ('created','updated','voided','restored')
      BEGIN
        INSERT INTO $outbox(outbox_id,change_id,organization_id,entity_type,
          entity_id,entity_uuid,operation,base_revision,revision,idempotency_key,
          occurred_at,payload_json,state,created_at,updated_at)
        VALUES(NEW.change_id,NEW.change_id,NEW.organization_id,NEW.entity_type,
          NEW.entity_id,NEW.entity_uuid,
          CASE WHEN NEW.operation='voided' THEN 'DELETE' ELSE 'UPSERT' END,
          CASE WHEN NEW.revision>0 THEN NEW.revision-1 ELSE 0 END,NEW.revision,
          'sync-change:' || NEW.change_id,NEW.occurred_at,
          COALESCE(NEW.after_json,NEW.before_json,'{}'),'PENDING',NEW.occurred_at,NEW.occurred_at);
      END''');

    await _backfillLocalChanges(db);
    await _installGuards(db);
  }

  static Future<void> _backfillLocalChanges(DatabaseExecutor db) async {
    await db.execute(
      '''INSERT OR IGNORE INTO $outbox(
      outbox_id,change_id,organization_id,entity_type,entity_id,entity_uuid,
      operation,base_revision,revision,idempotency_key,occurred_at,payload_json,
      state,created_at,updated_at)
      SELECT c.change_id,c.change_id,c.organization_id,c.entity_type,c.entity_id,
        c.entity_uuid,CASE WHEN c.operation='voided' THEN 'DELETE' ELSE 'UPSERT' END,
        CASE WHEN c.revision>0 THEN c.revision-1 ELSE 0 END,c.revision,
        'sync-change:' || c.change_id,c.occurred_at,
        COALESCE(c.after_json,c.before_json,'{}'),'PENDING',c.occurred_at,c.occurred_at
      FROM ${SyncFoundationTables.changes} c
      WHERE c.origin='local' AND c.operation IN ('created','updated','voided','restored')
        AND NOT EXISTS (SELECT 1 FROM $outbox o WHERE o.change_id=c.change_id)''',
    );
  }

  static Future<void> _installGuards(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS trg_sync_v3_outbox_identity_guard
      BEFORE UPDATE OF change_id,organization_id,entity_type,entity_id,entity_uuid,
        operation,base_revision,revision,idempotency_key,occurred_at,payload_json
      ON $outbox BEGIN SELECT RAISE(ABORT,'SYNC_OUTBOX_PAYLOAD_IMMUTABLE'); END''',
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS trg_sync_v3_outbox_no_delete
      BEFORE DELETE ON $outbox BEGIN SELECT RAISE(ABORT,'SYNC_OUTBOX_RETAINED'); END''',
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS trg_sync_v3_outbox_state_guard
      BEFORE UPDATE OF state ON $outbox
      WHEN NOT (
        (OLD.state='PENDING' AND NEW.state='SENDING') OR
        (OLD.state='SENDING' AND NEW.state IN ('PENDING','ACKNOWLEDGED','CONFLICT','REJECTED')) OR
        OLD.state=NEW.state
      ) BEGIN SELECT RAISE(ABORT,'SYNC_OUTBOX_INVALID_TRANSITION'); END''',
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS trg_sync_v3_inbox_identity_guard
      BEFORE UPDATE OF organization_id,server_sequence,change_id,entity_type,
        entity_id,entity_uuid,operation,revision,occurred_at,payload_json
      ON $inbox BEGIN SELECT RAISE(ABORT,'SYNC_INBOX_PAYLOAD_IMMUTABLE'); END''',
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS trg_sync_v3_inbox_no_delete
      BEFORE DELETE ON $inbox BEGIN SELECT RAISE(ABORT,'SYNC_INBOX_RETAINED'); END''',
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS trg_sync_v3_inbox_state_guard
      BEFORE UPDATE OF state ON $inbox
      WHEN NOT ((OLD.state='RECEIVED' AND NEW.state IN ('APPLIED','CONFLICT','REJECTED'))
        OR OLD.state=NEW.state)
      BEGIN SELECT RAISE(ABORT,'SYNC_INBOX_INVALID_TRANSITION'); END''',
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS trg_sync_v3_checkpoint_monotonic
      BEFORE UPDATE OF last_server_sequence ON $checkpoint
      WHEN NEW.last_server_sequence < OLD.last_server_sequence
      BEGIN SELECT RAISE(ABORT,'SYNC_CHECKPOINT_REGRESSION'); END''',
    );
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS trg_sync_v3_checkpoint_no_delete
      BEFORE DELETE ON $checkpoint BEGIN SELECT RAISE(ABORT,'SYNC_CHECKPOINT_RETAINED'); END''',
    );
  }

  static Future<void> validate(DatabaseExecutor db) async {
    for (final table in [outbox, inbox, checkpoint]) {
      final found = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      if (found.isEmpty) throw StateError('Phase 05 missing $table.');
    }
    final orphaned =
        Sqflite.firstIntValue(
          await db.rawQuery('''
      SELECT COUNT(*) FROM $outbox o LEFT JOIN ${SyncFoundationTables.changes} c
        ON c.change_id=o.change_id WHERE c.change_id IS NULL
    '''),
        ) ??
        0;
    if (orphaned != 0) throw StateError('Phase 05 orphaned sync outbox rows.');
  }
}
