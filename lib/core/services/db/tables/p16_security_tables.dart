import 'package:sqflite/sqflite.dart';

class P16SecurityTables {
  P16SecurityTables._();

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_audit_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        actor_user_id TEXT,
        actor_role TEXT,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        before_json TEXT,
        after_json TEXT,
        reason TEXT,
        device_id TEXT,
        session_id TEXT,
        metadata_json TEXT
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_audit_created
      ON app_audit_events(created_at DESC);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_audit_actor
      ON app_audit_events(actor_user_id, created_at DESC);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_audit_entity
      ON app_audit_events(entity_type, entity_id, created_at DESC);
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_app_audit_no_update
      BEFORE UPDATE ON app_audit_events
      BEGIN
        SELECT RAISE(ABORT, 'P16 audit events are append-only');
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_app_audit_no_delete
      BEFORE DELETE ON app_audit_events
      BEGIN
        SELECT RAISE(ABORT, 'P16 audit events are append-only');
      END;
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_guardian_settings (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        weekly_enabled INTEGER NOT NULL DEFAULT 1 CHECK(weekly_enabled IN (0,1)),
        backup_email TEXT,
        last_local_backup_at TEXT,
        last_external_handoff_at TEXT,
        next_due_at TEXT,
        snoozed_until TEXT,
        last_skipped_at TEXT,
        updated_at TEXT NOT NULL
      );
    ''');

    final now = DateTime.now().toUtc();
    await db.insert(
      'backup_guardian_settings',
      {
        'id': 1,
        'weekly_enabled': 1,
        'next_due_at': now.add(const Duration(days: 7)).toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        kind TEXT NOT NULL,
        local_path TEXT NOT NULL,
        status TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        db_version INTEGER,
        file_sha256 TEXT,
        includes_media INTEGER NOT NULL DEFAULT 1,
        external_handoff_at TEXT,
        external_target TEXT,
        manifest_json TEXT,
        error_text TEXT
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_backup_runs_created
      ON backup_runs(created_at DESC);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS windows_import_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        source_path TEXT NOT NULL,
        source_db_version INTEGER,
        safety_backup_path TEXT,
        status TEXT NOT NULL,
        note TEXT
      );
    ''');
  }
}
