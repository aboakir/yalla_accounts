import 'package:sqflite/sqflite.dart';

class AccountingPeriodGuard {
  AccountingPeriodGuard._();

  static const String closesTable = 'accounting_period_closes';
  static const String eventsTable = 'accounting_period_events';

  static Future<void> ensureSchemaOn(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $closesTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        period_start_utc TEXT NOT NULL,
        period_end_exclusive_utc TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'CLOSED'
          CHECK(status IN ('CLOSED','OPEN')),
        closed_at TEXT NOT NULL,
        closed_by TEXT,
        reopened_at TEXT,
        reopened_by TEXT,
        note TEXT,
        UNIQUE(period_start_utc, period_end_exclusive_utc)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_accounting_period_closes_status
      ON $closesTable(status, period_start_utc, period_end_exclusive_utc)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $eventsTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        close_id INTEGER NOT NULL,
        action TEXT NOT NULL CHECK(action IN ('CLOSE','REOPEN')),
        actor_id TEXT,
        reason TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_accounting_period_events_close
      ON $eventsTable(close_id, id)
    ''');

    final gl = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='gl_entries' LIMIT 1",
    );
    if (gl.isNotEmpty) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_gl_entries_closed_period_insert
        BEFORE INSERT ON gl_entries
        WHEN EXISTS(
          SELECT 1
          FROM $closesTable p
          WHERE p.status='CLOSED'
            AND NEW.date >= p.period_start_utc
            AND NEW.date < p.period_end_exclusive_utc
        )
        BEGIN
          SELECT RAISE(ABORT, 'ACCOUNTING_PERIOD_CLOSED');
        END
      ''');
    }
  }

  static Future<void> assertOpenOn(
    DatabaseExecutor db,
    DateTime date,
  ) async {
    if (!await _schemaExistsOn(db)) return;
    final iso = date.toUtc().toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT id
      FROM $closesTable
      WHERE status='CLOSED'
        AND ? >= period_start_utc
        AND ? < period_end_exclusive_utc
      LIMIT 1
      ''',
      [iso, iso],
    );
    if (rows.isNotEmpty) {
      throw StateError(
        'ACCOUNTING_PERIOD_CLOSED:${rows.single['id']}:$iso',
      );
    }
  }

  static Future<bool> isClosedOn(
    DatabaseExecutor db,
    DateTime date,
  ) async {
    if (!await _schemaExistsOn(db)) return false;
    final iso = date.toUtc().toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT 1
      FROM $closesTable
      WHERE status='CLOSED'
        AND ? >= period_start_utc
        AND ? < period_end_exclusive_utc
      LIMIT 1
      ''',
      [iso, iso],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _schemaExistsOn(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [closesTable],
    );
    return rows.isNotEmpty;
  }

  static DateTime localDayStartUtc(DateTime value) =>
      DateTime(value.year, value.month, value.day).toUtc();

  static DateTime localDayAfterUtc(DateTime value) =>
      DateTime(value.year, value.month, value.day)
          .add(const Duration(days: 1))
          .toUtc();
}
