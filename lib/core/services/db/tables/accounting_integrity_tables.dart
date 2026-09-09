import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// Stage 1 database-level accounting integrity guards.
class AccountingIntegrityTables {
  AccountingIntegrityTables._();

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<Set<String>> _columns(
    DatabaseExecutor db,
    String table,
  ) async {
    if (!await _tableExists(db, table)) return <String>{};
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
  }

  static Future<void> ensure(DatabaseExecutor db) async {
    await _ensureAuditEvents(db);
    await _ensureSourceDocumentGuards(db);
    await _ensurePostingGuards(db);
  }

  static Future<void> _ensurePostingGuards(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'gl_entries') ||
        !await _tableExists(db, 'gl_lines')) {
      return;
    }
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_gl_source_identity_insert
      BEFORE INSERT ON gl_entries
      BEGIN
        SELECT CASE WHEN LENGTH(TRIM(COALESCE(NEW.source,'')))=0
          OR LENGTH(TRIM(COALESCE(NEW.source_id,'')))=0
          THEN RAISE(ABORT,'GL_SOURCE_IDENTITY_REQUIRED') END;
        SELECT CASE WHEN EXISTS (SELECT 1 FROM gl_entries e
          WHERE TRIM(e.source_id)=TRIM(NEW.source_id)
            AND (CASE WHEN UPPER(TRIM(e.source))='PURCHASE_INVOICE' THEN 'PURCHASE'
              WHEN UPPER(TRIM(e.source))='PURCHASE_INVOICE_REV' THEN 'PURCHASE_REV'
              ELSE UPPER(TRIM(e.source)) END)
            = (CASE WHEN UPPER(TRIM(NEW.source))='PURCHASE_INVOICE' THEN 'PURCHASE'
              WHEN UPPER(TRIM(NEW.source))='PURCHASE_INVOICE_REV' THEN 'PURCHASE_REV'
              ELSE UPPER(TRIM(NEW.source)) END))
          THEN RAISE(ABORT,'GL_DUPLICATE_SOURCE_IDENTITY') END;
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_gl_line_values_guard
      BEFORE INSERT ON gl_lines
      BEGIN
        SELECT CASE WHEN NEW.debit IS NULL OR NEW.credit IS NULL
          OR typeof(NEW.debit) NOT IN ('real','integer') OR typeof(NEW.credit) NOT IN ('real','integer')
          OR NEW.debit<0 OR NEW.credit<0 OR (NEW.debit>0 AND NEW.credit>0)
          OR NEW.debit>90071992547409 OR NEW.credit>90071992547409
          OR ABS(NEW.debit*100-ROUND(NEW.debit*100))>0.000001
          OR ABS(NEW.credit*100-ROUND(NEW.credit*100))>0.000001
          THEN RAISE(ABORT,'GL_INVALID_LINE_AMOUNT') END;
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_gl_line_closed_entry
      BEFORE INSERT ON gl_lines
      WHEN EXISTS (SELECT 1 FROM accounting_audit_events WHERE gl_entry_id=NEW.entry_id)
      BEGIN SELECT RAISE(ABORT,'POSTED_GL_LINES_IMMUTABLE'); END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_gl_audit_balance_guard
      BEFORE INSERT ON accounting_audit_events
      WHEN NOT EXISTS (SELECT 1 FROM accounting_audit_events WHERE gl_entry_id=NEW.gl_entry_id)
      BEGIN
        SELECT CASE WHEN (SELECT COUNT(*) FROM gl_lines WHERE entry_id=NEW.gl_entry_id)<2
          OR (SELECT COALESCE(SUM(ROUND(debit*100)),0) FROM gl_lines WHERE entry_id=NEW.gl_entry_id)<=0
          OR (SELECT COALESCE(SUM(ROUND(debit*100)-ROUND(credit*100)),0) FROM gl_lines WHERE entry_id=NEW.gl_entry_id)<>0
          THEN RAISE(ABORT,'GL_UNBALANCED_ENTRY') END;
      END;
    ''');
  }

  static Future<void> _ensureAuditEvents(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'gl_entries')) return;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounting_audit_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gl_entry_id INTEGER NOT NULL UNIQUE REFERENCES gl_entries(id),
        event_type TEXT NOT NULL CHECK(event_type IN ('POST','REVERSAL')),
        source TEXT NOT NULL,
        source_id TEXT NOT NULL,
        canonical_source TEXT NOT NULL,
        reversal_of INTEGER,
        actor_user_id TEXT,
        created_at TEXT NOT NULL
      );
    ''');
    final auditColumns = await _columns(db, 'accounting_audit_events');
    for (final column in ['before_json', 'after_json']) {
      if (!auditColumns.contains(column)) {
        await db.execute(
            'ALTER TABLE accounting_audit_events ADD COLUMN $column TEXT');
      }
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_accounting_audit_source '
      'ON accounting_audit_events(canonical_source, source_id);',
    );

    // Safe historical backfill: no financial rows are changed. Older focused
    // schemas may not yet expose all GL metadata columns, so build the read
    // expressions from the actual table shape.
    final glColumns = await _columns(db, 'gl_entries');
    final reversalExpr =
        glColumns.contains('reversal_of') ? 'reversal_of' : 'NULL';
    final actorExpr = glColumns.contains('created_by') ? 'created_by' : 'NULL';
    final createdExpr = glColumns.contains('created_at')
        ? "COALESCE(created_at, date, datetime('now'))"
        : "COALESCE(date, datetime('now'))";
    await db.execute('''
      INSERT OR IGNORE INTO accounting_audit_events(
        gl_entry_id, event_type, source, source_id, canonical_source,
        reversal_of, actor_user_id, created_at
      )
      SELECT
        id,
        CASE WHEN $reversalExpr IS NULL THEN 'POST' ELSE 'REVERSAL' END,
        source,
        source_id,
        CASE
          WHEN UPPER(TRIM(source))='PURCHASE_INVOICE' THEN 'PURCHASE'
          WHEN UPPER(TRIM(source))='PURCHASE_INVOICE_REV' THEN 'PURCHASE_REV'
          ELSE UPPER(TRIM(source))
        END,
        $reversalExpr,
        $actorExpr,
        $createdExpr
      FROM gl_entries;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_accounting_audit_immutable_update
      BEFORE UPDATE ON accounting_audit_events
      BEGIN
        SELECT RAISE(ABORT, 'ACCOUNTING_AUDIT_IMMUTABLE');
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_accounting_audit_immutable_delete
      BEFORE DELETE ON accounting_audit_events
      BEGIN
        SELECT RAISE(ABORT, 'ACCOUNTING_AUDIT_IMMUTABLE');
      END;
    ''');
  }

  static Future<void> recordPostingEvent(
    DatabaseExecutor db, {
    required int glEntryId,
    required String source,
    required String sourceId,
    required String canonicalSource,
    required int? reversalOf,
    required String? actorUserId,
  }) async {
    if (!await _tableExists(db, 'accounting_audit_events')) return;
    Future<Map<String, Object?>> snapshot(int id) async => {
          'entry': await db.query('gl_entries', where: 'id=?', whereArgs: [id]),
          'lines':
              await db.query('gl_lines', where: 'entry_id=?', whereArgs: [id]),
        };
    final before = reversalOf == null ? null : await snapshot(reversalOf);
    final after = await snapshot(glEntryId);
    await db.insert(
      'accounting_audit_events',
      {
        'gl_entry_id': glEntryId,
        'event_type': reversalOf == null ? 'POST' : 'REVERSAL',
        'source': source,
        'source_id': sourceId,
        'canonical_source': canonicalSource,
        'reversal_of': reversalOf,
        'actor_user_id': actorUserId,
        'before_json': before == null ? null : jsonEncode(before),
        'after_json': jsonEncode(after),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _ensureSourceDocumentGuards(DatabaseExecutor db) async {
    await _guardHeader(
      db,
      table: 'invoices',
      sourcePredicate: "UPPER(source)='INVOICE'",
      protectedColumns: const [
        'client_id',
        'repair_id',
        'date',
        'subtotal',
        'vat',
        'vat_amount',
        'total',
      ],
      triggerPrefix: 'invoice',
    );
    await _guardHeader(
      db,
      table: 'purchase_invoices',
      sourcePredicate: "UPPER(source) IN ('PURCHASE','PURCHASE_INVOICE')",
      protectedColumns: const [
        'supplier_id',
        'date',
        'subtotal',
        'vat',
        'total',
        'amount_total',
        'purchase_type',
        'method',
      ],
      triggerPrefix: 'purchase',
    );

    if (await _tableExists(db, 'purchase_invoice_lines')) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_posted_purchase_lines_immutable_update
        BEFORE UPDATE ON purchase_invoice_lines
        WHEN EXISTS (
          SELECT 1 FROM gl_entries e
          WHERE UPPER(e.source) IN ('PURCHASE','PURCHASE_INVOICE')
            AND e.source_id=OLD.invoice_id
        )
        BEGIN
          SELECT RAISE(ABORT, 'POSTED_PURCHASE_LINES_IMMUTABLE_USE_REVERSAL');
        END;
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_posted_purchase_lines_immutable_delete
        BEFORE DELETE ON purchase_invoice_lines
        WHEN EXISTS (
          SELECT 1 FROM gl_entries e
          WHERE UPPER(e.source) IN ('PURCHASE','PURCHASE_INVOICE')
            AND e.source_id=OLD.invoice_id
        )
        BEGIN
          SELECT RAISE(ABORT, 'POSTED_PURCHASE_LINES_IMMUTABLE_USE_REVERSAL');
        END;
      ''');
    }
  }

  static Future<void> _guardHeader(
    DatabaseExecutor db, {
    required String table,
    required String sourcePredicate,
    required List<String> protectedColumns,
    required String triggerPrefix,
  }) async {
    if (!await _tableExists(db, table) ||
        !await _tableExists(db, 'gl_entries')) {
      return;
    }
    final columns = await _columns(db, table);
    final present = protectedColumns.where(columns.contains).toList();
    if (present.isNotEmpty) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_posted_${triggerPrefix}_financial_update
        BEFORE UPDATE OF ${present.join(', ')} ON $table
        WHEN EXISTS (
          SELECT 1 FROM gl_entries e
          WHERE $sourcePredicate AND e.source_id=OLD.id
        )
        BEGIN
          SELECT RAISE(ABORT, 'POSTED_${triggerPrefix.toUpperCase()}_IMMUTABLE_USE_REVERSAL');
        END;
      ''');
    }

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_posted_${triggerPrefix}_delete
      BEFORE DELETE ON $table
      WHEN EXISTS (
        SELECT 1 FROM gl_entries e
        WHERE $sourcePredicate AND e.source_id=OLD.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'POSTED_${triggerPrefix.toUpperCase()}_IMMUTABLE_USE_REVERSAL');
      END;
    ''');
  }
}
