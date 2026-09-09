import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import '../../gl_posting_policy.dart';
import '../../current_user_context.dart';
// 📁 lib/core/services/db/tables/accounting_tables.dart
import 'package:sqflite/sqflite.dart';
import 'payments_tables.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/core/services/accounting_source_policy.dart';
import 'accounting_integrity_tables.dart';
import 'party_tables.dart';

// أضف هذه الاستيرادات:

class AccountingTables {
  static int _postingSavepoint = 0;
  // 💰 إنشاء الجداول المحاسبية
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createAccountsTable(db);
    await ensureChartOfAccountsSchema(db);
    await _createGlEntriesTable(db);
    await _createGlLinesTable(db);
    await ensureGlCoreMetadataSchema(db);
    await PaymentsTables.createAllTables(db);

    await _createJournalEntriesTable(db);
    await _createLedgerEntriesTable(db);
    await _ensureInvoicesGlCol(db);
    await ensureInvoicesSchema(db);
    await ensureDefaultAccounts(db);
  }

  // 🏦 جدول الحسابات
  static Future<void> _createAccountsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE')),
        normal_balance TEXT CHECK(normal_balance IN ('DEBIT','CREDIT')),
        report_class TEXT
          CHECK(report_class IN (
            'ASSET','LIABILITY','EQUITY','REVENUE',
            'COGS','EXPENSE','OTHER_INCOME','OTHER_EXPENSE'
          )),
        parent_id INTEGER REFERENCES accounts(id),
        is_postable INTEGER NOT NULL DEFAULT 1
          CHECK(is_postable IN (0,1)),
        is_system INTEGER NOT NULL DEFAULT 0
          CHECK(is_system IN (0,1)),
        is_active INTEGER NOT NULL DEFAULT 1
          CHECK(is_active IN (0,1)),
        is_legacy INTEGER NOT NULL DEFAULT 0
          CHECK(is_legacy IN (0,1)),
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await _ensureAccountsIndexes(db);
  }

  static Future<void> _ensureAccountsIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_accounts_type ON accounts(type);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_accounts_name ON accounts(LOWER(name));');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_accounts_code ON accounts(code);');
    final info = await db.rawQuery('PRAGMA table_info(accounts)');
    final columns = info.map((row) => row['name']?.toString()).toSet();
    if (columns.contains('parent_id')) {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_accounts_parent ON accounts(parent_id);');
    }
    if (columns.contains('report_class')) {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_accounts_report_class ON accounts(report_class);');
    }
    if (columns.contains('is_active') && columns.contains('is_postable')) {
      await db
          .execute('CREATE INDEX IF NOT EXISTS idx_accounts_active_postable '
              'ON accounts(is_active, is_postable);');
    }
  }

  static Future<void> ensureInvoicesSchema(DatabaseExecutor db) async {
    await ensureColumnOn(
      db: db,
      table: 'invoices',
      column: 'subtotal',
      type: 'REAL',
    );

    await ensureColumnOn(
      db: db,
      table: 'invoices',
      column: 'vat',
      type: 'REAL',
    );

    await ensureColumnOn(
      db: db,
      table: 'invoices',
      column: 'total',
      type: 'REAL',
    );

    await ensureColumnOn(
      db: db,
      table: 'invoices',
      column: 'created_at',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'invoices',
      column: 'updated_at',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'invoices',
      column: 'client_id',
      type: 'INTEGER',
    );

    await ensureColumnOn(
      db: db,
      table: 'invoices',
      column: 'repair_id',
      type: 'TEXT',
    );
  }

  // 📒 جدول قيود اليومية
  static Future<void> _createGlEntriesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gl_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        ref TEXT,
        source TEXT NOT NULL,
        source_id TEXT NOT NULL,
        source_number TEXT,
        posting_version INTEGER NOT NULL DEFAULT 1
          CHECK(posting_version >= 1),
        reversal_of INTEGER REFERENCES gl_entries(id),
        created_by TEXT,
        note TEXT,
        created_at TEXT

      )
    ''');

    await _ensureGlEntriesIndexes(db);
  }

  static Future<void> _ensureGlEntriesIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gl_entries_date ON gl_entries(date);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gl_entries_source ON gl_entries(source, source_id);');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_gl_source ON gl_entries(source, source_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gl_entries_source_number '
        'ON gl_entries(source_number);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gl_entries_reversal_of '
        'ON gl_entries(reversal_of);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gl_entries_created_by '
        'ON gl_entries(created_by);');
    await db
        .execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_gl_entries_reversal_of '
            'ON gl_entries(reversal_of) WHERE reversal_of IS NOT NULL;');
  }

  // 📋 جدول بنود القيود
  static Future<void> _createGlLinesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gl_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL REFERENCES gl_entries(id) ON DELETE CASCADE,
        account_id INTEGER NOT NULL REFERENCES accounts(id),
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        party_type TEXT,
        party_id TEXT,
        invoice_id TEXT,
        repair_id TEXT,
        cheque_id INTEGER,
        reference_id TEXT,
        reference_type TEXT,
        created_at TEXT
      )
    ''');

    await _ensureGlLinesIndexes(db);
  }

  static Future<void> _ensureGlLinesIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gl_lines_entry ON gl_lines(entry_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gl_lines_account ON gl_lines(account_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gl_lines_party ON gl_lines(party_type, party_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gl_lines_invoice ON gl_lines(invoice_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gl_lines_repair ON gl_lines(repair_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gl_lines_cheque ON gl_lines(cheque_id);');
  }

  // 📔 الجداول القديمة (للتوافق)
  static Future<void> _createJournalEntriesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        description TEXT NOT NULL,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        accountName TEXT NOT NULL,
        relatedRepairId TEXT
      )
    ''');
  }

  static Future<void> _createLedgerEntriesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ledger_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        description TEXT,
        debit_account TEXT,
        credit_account TEXT,
        amount REAL,
        reference_type TEXT,
        reference_id TEXT,
        is_approved INTEGER DEFAULT 0,
        transaction_type TEXT
      )
    ''');
  }

  static Future<void> _ensureInvoicesGlCol(DatabaseExecutor db) async {
    await ensureColumnOn(
      db: db,
      table: 'invoices',
      column: 'gl_entry_id',
      type: 'INTEGER',
    );
  }

  // 🔄 ترقية الجداول
  static Future<void> onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 27) {
      await _createAccountsTable(db);
      await _createGlEntriesTable(db);
      await _createGlLinesTable(db);
    }

    if (oldV < 28) {
      await _ensureAccountsNormalBalance(db);
      await _ensureGlLinesInvoiceRepairCols(db);
    }

    if (oldV < 61) {
      await ensureGlCoreMetadataSchema(db);
    }

    if (oldV < 62) {
      await ensureChartOfAccountsSchema(db);
    }

    await ensureInvoicesSchema(db);
    await _ensureInvoicesGlCol(db);
    await ensureDefaultAccounts(db);

    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'created_at',
      type: 'TEXT',
    );
    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'created_at',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'updated_at',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'note',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'ref',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'source',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'source_id',
      type: 'TEXT',
    );
  }

  static Future<void> _ensureAccountsNormalBalance(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info(accounts)');
    final has = info.any((c) => (c['name'] as String?) == 'normal_balance');
    if (!has) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN normal_balance TEXT CHECK(normal_balance IN ('DEBIT','CREDIT'));",
      );
    }
  }

  // ============================================================
  // P1.007 — Chart of Accounts metadata / hierarchy / safety
  // ============================================================
  static String _reportClassForType(String type) {
    switch (type.toUpperCase()) {
      case 'ASSET':
        return 'ASSET';
      case 'LIABILITY':
        return 'LIABILITY';
      case 'EQUITY':
        return 'EQUITY';
      case 'REVENUE':
        return 'REVENUE';
      case 'EXPENSE':
        return 'EXPENSE';
      default:
        throw ArgumentError('Unsupported account type: $type');
    }
  }

  static String _normalBalanceForType(String type) {
    switch (type.toUpperCase()) {
      case 'ASSET':
      case 'EXPENSE':
        return 'DEBIT';
      case 'LIABILITY':
      case 'EQUITY':
      case 'REVENUE':
        return 'CREDIT';
      default:
        throw ArgumentError('Unsupported account type: $type');
    }
  }

  static Future<void> ensureChartOfAccountsSchema(
    DatabaseExecutor db,
  ) async {
    await ensureColumnOn(
      db: db,
      table: 'accounts',
      column: 'report_class',
      type: "TEXT CHECK(report_class IN "
          "('ASSET','LIABILITY','EQUITY','REVENUE',"
          "'COGS','EXPENSE','OTHER_INCOME','OTHER_EXPENSE'))",
    );
    await ensureColumnOn(
      db: db,
      table: 'accounts',
      column: 'parent_id',
      type: 'INTEGER REFERENCES accounts(id)',
    );
    await ensureColumnOn(
      db: db,
      table: 'accounts',
      column: 'is_postable',
      type: 'INTEGER NOT NULL DEFAULT 1 CHECK(is_postable IN (0,1))',
    );
    await ensureColumnOn(
      db: db,
      table: 'accounts',
      column: 'is_system',
      type: 'INTEGER NOT NULL DEFAULT 0 CHECK(is_system IN (0,1))',
    );
    await ensureColumnOn(
      db: db,
      table: 'accounts',
      column: 'is_active',
      type: 'INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1))',
    );
    await ensureColumnOn(
      db: db,
      table: 'accounts',
      column: 'is_legacy',
      type: 'INTEGER NOT NULL DEFAULT 0 CHECK(is_legacy IN (0,1))',
    );

    // Historical type already exists. Derive only metadata; never move GL.
    await db.execute(r'''
      UPDATE accounts
      SET normal_balance = CASE
            WHEN type IN ('ASSET','EXPENSE') THEN 'DEBIT'
            ELSE 'CREDIT'
          END
      WHERE normal_balance IS NULL OR TRIM(normal_balance) = '';
    ''');

    await db.execute(r'''
      UPDATE accounts
      SET report_class = CASE type
            WHEN 'ASSET' THEN 'ASSET'
            WHEN 'LIABILITY' THEN 'LIABILITY'
            WHEN 'EQUITY' THEN 'EQUITY'
            WHEN 'REVENUE' THEN 'REVENUE'
            WHEN 'EXPENSE' THEN 'EXPENSE'
          END
      WHERE report_class IS NULL OR TRIM(report_class) = '';
    ''');

    // Parent hierarchy. Historical employee advances stay on their original
    // account ids but are classified under the correct 1120 family.
    await db.execute(r'''
      UPDATE accounts
      SET parent_id = CASE
        WHEN code LIKE '1200.C%' THEN
          (SELECT id FROM accounts WHERE code='1200' LIMIT 1)
        WHEN code LIKE '1120.E%' OR code LIKE '1200.E%' THEN
          (SELECT id FROM accounts WHERE code='1120' LIMIT 1)
        WHEN code LIKE '2140.E%' THEN
          (SELECT id FROM accounts WHERE code='2140' LIMIT 1)
        WHEN code GLOB '2200.S[0-9]*'
          OR code LIKE '2200.SS%'
          OR code LIKE '2000.S%' THEN
          (SELECT id FROM accounts WHERE code='2200' LIMIT 1)
        ELSE parent_id
      END
      WHERE code LIKE '1200.C%'
         OR code LIKE '1120.E%'
         OR code LIKE '1200.E%'
         OR code LIKE '2140.E%'
         OR code GLOB '2200.S[0-9]*'
         OR code LIKE '2200.SS%'
         OR code LIKE '2000.S%';
    ''');

    await db.execute(r'''
      UPDATE accounts
      SET is_system = 1
      WHERE code IN (
        '1000','1010','1020','1030','1120','1200','1400','1410',
        '2100','2105','2140','2145','2200','3100','4000',
        '5005','5100','5310','5350','5900'
      )
      OR code LIKE '1120.E%'
      OR code LIKE '1200.C%'
      OR code LIKE '1200.E%'
      OR code LIKE '2140.E%'
      OR code GLOB '2200.S[0-9]*'
      OR code LIKE '2200.SS%'
      OR code LIKE '2000.S%';
    ''');

    await db.execute(r'''
      UPDATE accounts
      SET is_postable = 0
      WHERE code IN ('1120','1200','2140','2200')
         OR code LIKE '1200.E%'
         OR code LIKE '2200.SS%'
         OR code LIKE '2000.S%';
    ''');

    // Retire obsolete supplier aliases. Historical GL remains untouched.
    await db.execute(r'''
      UPDATE accounts
      SET is_legacy = 1,
          is_active = CASE
            WHEN code LIKE '1200.E%' THEN is_active
            ELSE 0
          END,
          is_postable = 0
      WHERE code LIKE '1200.E%'
         OR code LIKE '2200.SS%'
         OR code LIKE '2000.S%';
    ''');

    await _ensureAccountsIndexes(db);

    // Do not allow the three obsolete account-code families to return.
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_block_legacy_insert
      BEFORE INSERT ON accounts
      WHEN NEW.code LIKE '1200.E%'
        OR NEW.code LIKE '2000.S%'
        OR NEW.code LIKE '2200.SS%'
      BEGIN
        SELECT RAISE(ABORT, 'LEGACY_ACCOUNT_CODE_BLOCKED');
      END;
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_code_required_insert
      BEFORE INSERT ON accounts
      WHEN NEW.code IS NULL OR TRIM(NEW.code) = ''
      BEGIN
        SELECT RAISE(ABORT, 'ACCOUNT_CODE_REQUIRED');
      END;
    ''');

    // Normalize metadata for older direct account-creation paths.
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_metadata_after_insert
      AFTER INSERT ON accounts
      BEGIN
        UPDATE accounts
        SET normal_balance = COALESCE(
              NULLIF(normal_balance,''),
              CASE
                WHEN type IN ('ASSET','EXPENSE') THEN 'DEBIT'
                ELSE 'CREDIT'
              END
            ),
            report_class = COALESCE(
              NULLIF(report_class,''),
              CASE type
                WHEN 'ASSET' THEN 'ASSET'
                WHEN 'LIABILITY' THEN 'LIABILITY'
                WHEN 'EQUITY' THEN 'EQUITY'
                WHEN 'REVENUE' THEN 'REVENUE'
                WHEN 'EXPENSE' THEN 'EXPENSE'
              END
            ),
            parent_id = COALESCE(
              parent_id,
              CASE
                WHEN code LIKE '1200.C%' THEN
                  (SELECT id FROM accounts WHERE code='1200' LIMIT 1)
                WHEN code LIKE '1120.E%' THEN
                  (SELECT id FROM accounts WHERE code='1120' LIMIT 1)
                WHEN code LIKE '2140.E%' THEN
                  (SELECT id FROM accounts WHERE code='2140' LIMIT 1)
                WHEN code GLOB '2200.S[0-9]*' THEN
                  (SELECT id FROM accounts WHERE code='2200' LIMIT 1)
                ELSE NULL
              END
            ),
            is_system = CASE
              WHEN code IN (
                '1000','1010','1020','1030','1120','1200','1400','1410',
                '2100','2105','2140','2145','2200','3100','4000',
                '5005','5100','5310','5350','5900'
              )
              OR code LIKE '1120.E%'
              OR code LIKE '1200.C%'
              OR code LIKE '2140.E%'
              OR code GLOB '2200.S[0-9]*'
              THEN 1 ELSE is_system END,
            is_postable = CASE
              WHEN code IN ('1120','1200','2140','2200')
              THEN 0 ELSE is_postable END
        WHERE id = NEW.id;
      END;
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_code_required_update
      BEFORE UPDATE OF code ON accounts
      WHEN NEW.code IS NULL OR TRIM(NEW.code) = ''
      BEGIN
        SELECT RAISE(ABORT, 'ACCOUNT_CODE_REQUIRED');
      END;
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_block_legacy_code_update
      BEFORE UPDATE OF code ON accounts
      WHEN NEW.code LIKE '1200.E%'
        OR NEW.code LIKE '2000.S%'
        OR NEW.code LIKE '2200.SS%'
      BEGIN
        SELECT RAISE(ABORT, 'LEGACY_ACCOUNT_CODE_BLOCKED');
      END;
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_normalize_after_code_update
      AFTER UPDATE OF code ON accounts
      WHEN NEW.code <> OLD.code
      BEGIN
        UPDATE accounts
        SET parent_id = CASE
              WHEN NEW.code LIKE '1200.C%' THEN
                (SELECT id FROM accounts WHERE code='1200' LIMIT 1)
              WHEN NEW.code LIKE '1120.E%' THEN
                (SELECT id FROM accounts WHERE code='1120' LIMIT 1)
              WHEN NEW.code LIKE '2140.E%' THEN
                (SELECT id FROM accounts WHERE code='2140' LIMIT 1)
              WHEN NEW.code GLOB '2200.S[0-9]*' THEN
                (SELECT id FROM accounts WHERE code='2200' LIMIT 1)
              ELSE NULL
            END,
            is_system = CASE
              WHEN NEW.code IN (
                '1000','1010','1020','1030','1120','1200','1400','1410',
                '2100','2105','2140','2145','2200','3100','4000',
                '5005','5100','5310','5350','5900'
              )
              OR NEW.code LIKE '1120.E%'
              OR NEW.code LIKE '1200.C%'
              OR NEW.code LIKE '2140.E%'
              OR NEW.code GLOB '2200.S[0-9]*'
              THEN 1 ELSE 0 END,
            is_postable = CASE
              WHEN NEW.code IN ('1120','1200','2140','2200')
              THEN 0 ELSE 1 END
        WHERE id = NEW.id;
      END;
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_protect_identity
      BEFORE UPDATE OF code, type, normal_balance ON accounts
      WHEN (
          OLD.is_system = 1
          OR EXISTS(
            SELECT 1 FROM gl_lines l WHERE l.account_id = OLD.id LIMIT 1
          )
        )
        AND (
          NEW.code IS NOT OLD.code
          OR NEW.type IS NOT OLD.type
          OR (
            NEW.normal_balance IS NOT OLD.normal_balance
            AND NOT (
              NOT EXISTS(
                SELECT 1
                FROM gl_lines l
                WHERE l.account_id = OLD.id
                LIMIT 1
              )
              AND (
                OLD.normal_balance IS NULL
                OR TRIM(OLD.normal_balance) = ''
              )
              AND NEW.normal_balance = CASE
                WHEN OLD.type IN ('ASSET','EXPENSE') THEN 'DEBIT'
                ELSE 'CREDIT'
              END
            )
          )
        )
      BEGIN
        SELECT RAISE(ABORT, 'ACCOUNT_IDENTITY_IMMUTABLE');
      END;
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_normalize_after_type_update
      AFTER UPDATE OF type ON accounts
      WHEN NEW.type <> OLD.type
      BEGIN
        UPDATE accounts
        SET normal_balance = CASE
              WHEN NEW.type IN ('ASSET','EXPENSE') THEN 'DEBIT'
              ELSE 'CREDIT'
            END,
            report_class = CASE NEW.type
              WHEN 'ASSET' THEN 'ASSET'
              WHEN 'LIABILITY' THEN 'LIABILITY'
              WHEN 'EQUITY' THEN 'EQUITY'
              WHEN 'REVENUE' THEN 'REVENUE'
              WHEN 'EXPENSE' THEN 'EXPENSE'
            END
        WHERE id = NEW.id;
      END;
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_parent_not_self
      BEFORE UPDATE OF parent_id ON accounts
      WHEN NEW.parent_id = OLD.id
      BEGIN
        SELECT RAISE(ABORT, 'ACCOUNT_PARENT_SELF_REFERENCE');
      END;
    ''');

    for (final event in ['INSERT', 'UPDATE OF parent_id, type']) {
      final suffix = event.startsWith('INSERT') ? 'insert' : 'update';
      await db.execute("""
        CREATE TRIGGER IF NOT EXISTS trg_accounts_parent_valid_$suffix
        BEFORE $event ON accounts WHEN NEW.parent_id IS NOT NULL
        BEGIN
          SELECT RAISE(ABORT,'ACCOUNT_PARENT_MISSING') WHERE NOT EXISTS
            (SELECT 1 FROM accounts WHERE id=NEW.parent_id);
          SELECT RAISE(ABORT,'ACCOUNT_PARENT_TYPE') WHERE EXISTS
            (SELECT 1 FROM accounts WHERE id=NEW.parent_id AND UPPER(type)<>UPPER(NEW.type));
          SELECT RAISE(ABORT,'ACCOUNT_PARENT_CYCLE') WHERE NEW.id IN (
            WITH RECURSIVE ancestors(id,parent_id) AS (
              SELECT id,parent_id FROM accounts WHERE id=NEW.parent_id
              UNION SELECT a.id,a.parent_id FROM accounts a JOIN ancestors p ON a.id=p.parent_id
            ) SELECT id FROM ancestors);
          SELECT RAISE(ABORT,'ACCOUNT_CHILD_TYPE') WHERE EXISTS
            (SELECT 1 FROM accounts WHERE parent_id=NEW.id AND UPPER(type)<>UPPER(NEW.type));
        END;
      """);
    }
    await db
        .execute("""CREATE TRIGGER IF NOT EXISTS trg_accounts_child_type_update
      BEFORE UPDATE OF type ON accounts WHEN EXISTS
        (SELECT 1 FROM accounts WHERE parent_id=OLD.id AND UPPER(type)<>UPPER(NEW.type))
      BEGIN SELECT RAISE(ABORT,'ACCOUNT_CHILD_TYPE'); END;""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS trg_accounts_parent_delete
      BEFORE DELETE ON accounts WHEN EXISTS(SELECT 1 FROM accounts WHERE parent_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'ACCOUNT_HAS_CHILDREN'); END;""");

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_accounts_protect_delete
      BEFORE DELETE ON accounts
      WHEN OLD.is_system = 1
        OR EXISTS(
          SELECT 1 FROM gl_lines l WHERE l.account_id = OLD.id LIMIT 1
        )
      BEGIN
        SELECT RAISE(ABORT, 'ACCOUNT_DELETE_PROTECTED');
      END;
    ''');
  }

  static Future<void> _ensureGlLinesInvoiceRepairCols(
      DatabaseExecutor db) async {
    await ensureColumnOn(
        db: db, table: 'gl_lines', column: 'invoice_id', type: 'TEXT');
    await ensureColumnOn(
        db: db, table: 'gl_lines', column: 'repair_id', type: 'TEXT');
    await ensureColumnOn(
        db: db, table: 'gl_lines', column: 'reference_id', type: 'TEXT');
    await ensureColumnOn(
        db: db, table: 'gl_lines', column: 'reference_type', type: 'TEXT');
    await ensureColumnOn(
        db: db, table: 'gl_lines', column: 'created_at', type: 'TEXT');
  }

  // ============================================================
  // P1.006 — GL metadata + immutable posted-ledger protection
  // ============================================================
  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master "
      "WHERE type='table' AND name=? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<void> ensureGlCoreMetadataSchema(
    DatabaseExecutor db,
  ) async {
    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'source_number',
      type: 'TEXT',
    );
    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'posting_version',
      type: 'INTEGER NOT NULL DEFAULT 1 CHECK(posting_version >= 1)',
    );
    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'reversal_of',
      type: 'INTEGER REFERENCES gl_entries(id)',
    );
    await ensureColumnOn(
      db: db,
      table: 'gl_entries',
      column: 'created_by',
      type: 'TEXT',
    );

    await db.execute(r'''
      UPDATE gl_entries
      SET posting_version = 1
      WHERE posting_version IS NULL OR posting_version < 1;
    ''');

    if (await _tableExists(db, 'vouchers')) {
      await db.execute(r'''
        UPDATE gl_entries
        SET source_number = (
          SELECT v.voucher_number
          FROM vouchers v
          WHERE v.id = gl_entries.source_id
          LIMIT 1
        )
        WHERE source = 'VOUCHER'
          AND (source_number IS NULL OR TRIM(source_number) = '')
          AND EXISTS (
            SELECT 1
            FROM vouchers v
            WHERE v.id = gl_entries.source_id
              AND v.voucher_number IS NOT NULL
              AND TRIM(v.voucher_number) <> ''
          );
      ''');
    }

    await db.execute(r'''
      UPDATE gl_entries AS rev
      SET reversal_of = (
        SELECT original.id
        FROM gl_entries original
        WHERE original.source = 'INVOICE'
          AND rev.source_id = original.source_id || '_REV'
        LIMIT 1
      )
      WHERE rev.source = 'INVOICE_REV'
        AND rev.reversal_of IS NULL
        AND EXISTS (
          SELECT 1
          FROM gl_entries original
          WHERE original.source = 'INVOICE'
            AND rev.source_id = original.source_id || '_REV'
        );
    ''');

    await db.execute(r'''
      UPDATE gl_entries AS rev
      SET reversal_of = (
        SELECT original.id
        FROM gl_entries original
        WHERE original.source = 'INVOICE'
          AND original.source_id = rev.source_id
        LIMIT 1
      )
      WHERE rev.source = 'P0_DUP_REV'
        AND rev.reversal_of IS NULL
        AND EXISTS (
          SELECT 1
          FROM gl_entries original
          WHERE original.source = 'INVOICE'
            AND original.source_id = rev.source_id
        );
    ''');

    await db.execute(r'''
      UPDATE gl_entries
      SET reversal_of = CAST(source_id AS INTEGER)
      WHERE source = 'P0_REPAIR_FIX'
        AND reversal_of IS NULL
        AND source_id GLOB '[0-9]*'
        AND CAST(source_id AS INTEGER) <> id
        AND EXISTS (
          SELECT 1
          FROM gl_entries original
          WHERE original.id = CAST(gl_entries.source_id AS INTEGER)
        );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gl_entries_source_number '
      'ON gl_entries(source_number);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gl_entries_reversal_of '
      'ON gl_entries(reversal_of);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gl_entries_created_by '
      'ON gl_entries(created_by);',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_gl_entries_reversal_of '
      'ON gl_entries(reversal_of) WHERE reversal_of IS NOT NULL;',
    );

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_gl_entries_immutable_update
      BEFORE UPDATE ON gl_entries
      BEGIN
        SELECT RAISE(ABORT, 'POSTED_GL_ENTRY_IMMUTABLE');
      END;
    ''');
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_gl_entries_immutable_delete
      BEFORE DELETE ON gl_entries
      BEGIN
        SELECT RAISE(ABORT, 'POSTED_GL_ENTRY_IMMUTABLE');
      END;
    ''');
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_gl_lines_immutable_update
      BEFORE UPDATE ON gl_lines
      BEGIN
        SELECT RAISE(ABORT, 'POSTED_GL_LINE_IMMUTABLE');
      END;
    ''');
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_gl_lines_immutable_delete
      BEFORE DELETE ON gl_lines
      BEGIN
        SELECT RAISE(ABORT, 'POSTED_GL_LINE_IMMUTABLE');
      END;
    ''');
  }

  // 🎯 الحسابات الافتراضية
  static Future<void> ensureDefaultAccounts(DatabaseExecutor db) async {
    final defaultAccounts = [
      {
        'code': '1000',
        'name': 'الصندوق',
        'type': 'ASSET',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '1010',
        'name': 'البنك',
        'type': 'ASSET',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '1200',
        'name': 'ذمم العملاء',
        'type': 'ASSET',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '1120',
        'name': 'سلف الموظفين',
        'type': 'ASSET',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '1400',
        'name': 'مخزون/مشتريات',
        'type': 'ASSET',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '1410',
        'name': 'مخزون قطع سيارات',
        'type': 'ASSET',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '2100',
        'name': 'ذمم الموردين (عام)',
        'type': 'LIABILITY',
        'normal_balance': 'CREDIT'
      },
      {
        'code': '2200',
        'name': 'ذمم الموردين الفرعية',
        'type': 'LIABILITY',
        'normal_balance': 'CREDIT'
      },
      {
        'code': '2140',
        'name': 'مستحقات موظفين',
        'type': 'LIABILITY',
        'normal_balance': 'CREDIT'
      },
      {
        'code': '2145',
        'name': 'اقتطاعات مستحقة',
        'type': 'LIABILITY',
        'normal_balance': 'CREDIT'
      },
      {
        'code': '2105',
        'name': 'ضريبة قيمة مضافة مستحقة',
        'type': 'LIABILITY',
        'normal_balance': 'CREDIT'
      },
      {
        'code': '3100',
        'name': 'أرصدة افتتاحية',
        'type': 'EQUITY',
        'normal_balance': 'CREDIT'
      },
      {
        'code': '4000',
        'name': 'الإيرادات',
        'type': 'REVENUE',
        'normal_balance': 'CREDIT'
      },
      {
        'code': '5005',
        'name': 'مشتريات',
        'type': 'EXPENSE',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '5100',
        'name': 'مصروف رواتب',
        'type': 'EXPENSE',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '5310',
        'name': 'مصروف مواد خام مستهلكة',
        'type': 'EXPENSE',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '5350',
        'name': 'مصروف عدة كراج وأدوات',
        'type': 'EXPENSE',
        'normal_balance': 'DEBIT'
      },
      {
        'code': '5900',
        'name': 'مصروفات أخرى',
        'type': 'EXPENSE',
        'normal_balance': 'DEBIT'
      },
    ];

    for (final account in defaultAccounts) {
      await _ensureAccount(db, account);
    }
  }

  static Future<void> _ensureAccount(
      DatabaseExecutor db, Map<String, String> account) async {
    final existing = await db.query(
      'accounts',
      where: 'code = ?',
      whereArgs: [account['code']],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      if (row['type']?.toString() != account['type'] ||
          row['normal_balance']?.toString() != account['normal_balance']) {
        throw StateError(
          'Account ${account['code']} exists with a conflicting '
          'type/normal balance.',
        );
      }
      return;
    }

    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert('accounts', {
              ...account,
              'report_class': _reportClassForType(account['type']!),
              'is_system': 1,
              'created_at': DateTime.now().toIso8601String(),
            }));
  }

  // 🎯 واجهات المحاسبة الرئيسية
  static Future<int> postEntryGL({
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? sourceNumber,
    int postingVersion = 1,
    String? createdBy,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    final db = await DBService.database;
    return await SyncFoundationService.transaction(
      db,
      (txn) => _postEntryGLOn(
        db: txn,
        date: date,
        ref: ref,
        source: source,
        sourceId: sourceId,
        sourceNumber: sourceNumber,
        postingVersion: postingVersion,
        createdBy: createdBy,
        note: note,
        lines: lines,
      ),
    );
  }

  static Future<int> postEntryGLOn({
    required DatabaseExecutor ex,
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? sourceNumber,
    int postingVersion = 1,
    String? createdBy,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    return await _postEntryGLOn(
      db: ex,
      date: date,
      ref: ref,
      source: source,
      sourceId: sourceId,
      sourceNumber: sourceNumber,
      postingVersion: postingVersion,
      createdBy: createdBy,
      note: note,
      lines: lines,
    );
  }

  static Future<bool> _accountsHaveCoaMetadata(
    DatabaseExecutor db,
  ) async {
    if (!await _tableExists(db, 'accounts')) return false;

    final info = await db.rawQuery('PRAGMA table_info(accounts)');
    final names = info.map((row) => row['name']?.toString()).toSet();

    return names.contains('is_postable') &&
        names.contains('is_active') &&
        names.contains('report_class');
  }

  static Future<void> _validatePostingAccounts(
    DatabaseExecutor db,
    List<Map<String, Object?>> lines, {
    required bool allowRetiredForReversal,
  }) async {
    // Compatibility with focused legacy unit-test schemas created before
    // P1.007. Production v62 always has the metadata columns.
    if (!await _accountsHaveCoaMetadata(db)) return;

    final accountIds = <int>{};
    for (final line in lines) {
      final raw = line['account_id'];
      final id = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
      if (id == null || id <= 0) {
        throw StateError('Posting line has an invalid account_id.');
      }
      accountIds.add(id);
    }

    if (accountIds.isEmpty) {
      throw StateError('Posting requires at least one account.');
    }

    final placeholders = List.filled(accountIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT id, code, is_active, is_postable '
      'FROM accounts WHERE id IN ($placeholders)',
      accountIds.toList(),
    );

    if (rows.length != accountIds.length) {
      final found = rows.map((row) => (row['id'] as num).toInt()).toSet();
      final missing = accountIds.where((id) => !found.contains(id)).toList();
      throw StateError('Posting references missing account ids: $missing');
    }

    if (allowRetiredForReversal) return;

    for (final row in rows) {
      final active = (row['is_active'] as num?)?.toInt() ?? 0;
      final postable = (row['is_postable'] as num?)?.toInt() ?? 0;
      if (active != 1 || postable != 1) {
        throw StateError(
          'Account ${row['code']} is inactive or non-postable. '
          'Posting stopped.',
        );
      }
    }
  }

// ============================================================================
// 🔥 النسخة النهائية — بدون أي DB جديدة — تعتمد فقط على نفس الـ txn
// ============================================================================
  static Future<int> _postEntryGLOn({
    required DatabaseExecutor db,
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? sourceNumber,
    int postingVersion = 1,
    int? reversalOf,
    String? createdBy,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    if (db is Database) {
      return SyncFoundationService.transaction(
          db,
          (txn) => _writeEntryGLOn(
              db: txn,
              date: date,
              ref: ref,
              source: source,
              sourceId: sourceId,
              sourceNumber: sourceNumber,
              postingVersion: postingVersion,
              reversalOf: reversalOf,
              createdBy: createdBy,
              note: note,
              lines: lines));
    }
    final savepoint = 'gl_post_${++_postingSavepoint}';
    await db.execute('SAVEPOINT $savepoint');
    try {
      final id = await _writeEntryGLOn(
          db: db,
          date: date,
          ref: ref,
          source: source,
          sourceId: sourceId,
          sourceNumber: sourceNumber,
          postingVersion: postingVersion,
          reversalOf: reversalOf,
          createdBy: createdBy,
          note: note,
          lines: lines);
      await db.execute('RELEASE SAVEPOINT $savepoint');
      return id;
    } catch (_) {
      await db.execute('ROLLBACK TO SAVEPOINT $savepoint');
      await db.execute('RELEASE SAVEPOINT $savepoint');
      rethrow;
    }
  }

  static Future<int> _writeEntryGLOn({
    required DatabaseExecutor db,
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? sourceNumber,
    int postingVersion = 1,
    int? reversalOf,
    String? createdBy,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    if (postingVersion < 1) {
      throw ArgumentError('postingVersion must be >= 1');
    }
    if (reversalOf != null && reversalOf <= 0) {
      throw ArgumentError('reversalOf must reference a positive GL entry id');
    }

    final canonicalSource = AccountingSourcePolicy.canonical(source);
    if (canonicalSource.isEmpty) {
      throw ArgumentError('Accounting source is required.');
    }
    final cleanSourceId = sourceId.trim();
    if (cleanSourceId.isEmpty) {
      throw ArgumentError('Accounting sourceId is required.');
    }

    // Stage 1: all new Party metadata is canonicalized at the GL gateway.
    // Historical CLIENT/S0001 rows remain readable through Party views.
    final normalizedLines = <Map<String, Object?>>[];
    for (final raw in GlPostingPolicy.normalize(lines)) {
      final line = Map<String, Object?>.from(raw);
      final rawRole = line['party_type']?.toString().trim();
      final rawPartyId = line['party_id'];
      final hasRole = rawRole != null && rawRole.isNotEmpty;
      final hasParty =
          rawPartyId != null && rawPartyId.toString().trim().isNotEmpty;
      if (hasRole != hasParty) {
        throw StateError(
          'GL Party identity is incomplete for $canonicalSource:$cleanSourceId.',
        );
      }
      if (hasRole) {
        final role = PartyTables.canonicalRole(rawRole);
        if (PartyTables.supportedRoles.contains(role)) {
          line['party_type'] = role;
          line['party_id'] = PartyTables.canonicalLegacyId(role, rawPartyId);
        }
      }
      normalizedLines.add(line);
    }

    double numberValue(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    String nullableValue(Object? value) => value?.toString() ?? '';

    String lineSignature(Map<String, Object?> rawLine) {
      final line = Map<String, Object?>.from(rawLine);
      final role = PartyTables.canonicalRole(line['party_type']);
      if (PartyTables.supportedRoles.contains(role)) {
        line['party_type'] = role;
        line['party_id'] =
            PartyTables.canonicalLegacyId(role, line['party_id']);
      }
      return <String>[
        nullableValue(line['account_id']),
        numberValue(line['debit']).toStringAsFixed(6),
        numberValue(line['credit']).toStringAsFixed(6),
        nullableValue(line['party_type']),
        nullableValue(line['party_id']),
        nullableValue(line['invoice_id']),
        nullableValue(line['repair_id']),
        nullableValue(line['cheque_id']),
      ].join('|');
    }

    bool sameFinancialLines(
      List<Map<String, Object?>> existing,
      List<Map<String, Object?>> requested,
    ) {
      if (existing.length != requested.length) return false;
      final left = existing.map(lineSignature).toList()..sort();
      final right = requested.map(lineSignature).toList()..sort();
      for (var i = 0; i < left.length; i++) {
        if (left[i] != right[i]) return false;
      }
      return true;
    }

    Future<List<Map<String, Object?>>> findExistingEntries() async {
      final columns = <String>['id', 'source', 'date', 'ref', 'note'];
      if (sourceNumber != null || postingVersion != 1 || reversalOf != null) {
        columns.addAll(['source_number', 'posting_version', 'reversal_of']);
      }
      final aliases = AccountingSourcePolicy.aliasesFor(canonicalSource);
      final placeholders = List.filled(aliases.length, '?').join(',');
      return db.query(
        'gl_entries',
        columns: columns,
        where: 'UPPER(source) IN ($placeholders) AND source_id = ?',
        whereArgs: <Object?>[...aliases, cleanSourceId],
        orderBy: 'id ASC',
      );
    }

    Future<int> validateAndReturnExisting(
      Map<String, Object?> existingHead,
    ) async {
      final entryId = (existingHead['id'] as num).toInt();
      if (DateTime.tryParse('${existingHead['date']}') != date ||
          (ref != null &&
              ref.trim().isNotEmpty &&
              existingHead['ref'] != ref.trim()) ||
          (note != null &&
              note.trim().isNotEmpty &&
              existingHead['note'] != note.trim())) {
        throw StateError(
            'Posting identity reused with different date/reference/description');
      }

      if (sourceNumber != null &&
          existingHead.containsKey('source_number') &&
          existingHead['source_number'] != null &&
          existingHead['source_number'].toString() != sourceNumber) {
        throw StateError(
          'GL posting conflict for $canonicalSource:$cleanSourceId — '
          'source_number differs from the immutable existing entry.',
        );
      }
      if (existingHead.containsKey('posting_version')) {
        final existingVersion =
            (existingHead['posting_version'] as num?)?.toInt() ?? 1;
        if (existingVersion != postingVersion) {
          throw StateError(
            'GL posting conflict for $canonicalSource:$cleanSourceId — '
            'posting_version differs from the immutable existing entry.',
          );
        }
      }
      if (reversalOf != null &&
          existingHead.containsKey('reversal_of') &&
          existingHead['reversal_of'] != reversalOf) {
        throw StateError(
          'GL posting conflict for $canonicalSource:$cleanSourceId — '
          'reversal linkage differs from the immutable existing entry.',
        );
      }

      final existingLines = await db.query(
        'gl_lines',
        where: 'entry_id = ?',
        whereArgs: [entryId],
        orderBy: 'id ASC',
      );
      if (existingLines.isEmpty) {
        throw StateError(
          'GL posting conflict for $canonicalSource:$cleanSourceId — '
          'entry $entryId exists without lines. Posting stopped.',
        );
      }
      if (!sameFinancialLines(existingLines, normalizedLines)) {
        throw StateError(
          'GL posting conflict for $canonicalSource:$cleanSourceId — '
          'entry $entryId already exists with different financial lines. '
          'Posting stopped to prevent duplication/corruption.',
        );
      }
      return entryId;
    }

    final existingBeforeInsert = await findExistingEntries();
    if (existingBeforeInsert.length > 1) {
      throw StateError(
        'Duplicate legacy GL identity for $canonicalSource:$cleanSourceId — '
        'multiple source aliases already exist. Resolve by formal audit/reversal.',
      );
    }
    if (existingBeforeInsert.isNotEmpty) {
      return validateAndReturnExisting(existingBeforeInsert.single);
    }

    await _validatePostingAccounts(
      db,
      normalizedLines,
      allowRetiredForReversal: reversalOf != null,
    );

    final columns = await db.rawQuery('PRAGMA table_info(gl_entries)');
    final supportsActor = columns.any((c) => c['name'] == 'created_by');
    final actor = (createdBy?.trim().isNotEmpty ?? false)
        ? createdBy!.trim()
        : (supportsActor ? await CurrentUserContext.userId() : null);
    if (supportsActor && (actor == null || actor.isEmpty)) {
      throw StateError('يجب تسجيل الدخول قبل ترحيل قيد محاسبي');
    }
    final resolvedRef = GlPostingPolicy.reference(
        canonicalSource, cleanSourceId, ref, sourceNumber);
    final resolvedNote =
        GlPostingPolicy.description(canonicalSource, resolvedRef, note);
    final header = <String, Object?>{
      'date': date.toIso8601String(),
      'ref': resolvedRef,
      'source': canonicalSource,
      'source_id': cleanSourceId,
      'note': resolvedNote,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (sourceNumber != null && sourceNumber.trim().isNotEmpty) {
      header['source_number'] = sourceNumber.trim();
    }
    if (postingVersion != 1) header['posting_version'] = postingVersion;
    if (reversalOf != null) header['reversal_of'] = reversalOf;
    if (supportsActor && actor != null) {
      header['created_by'] = actor;
    }

    int entryId;
    try {
      entryId = await db.insert('gl_entries', header);
    } on DatabaseException catch (e) {
      if (!e.toString().contains('UNIQUE')) rethrow;
      final collision = await findExistingEntries();
      if (collision.length != 1) rethrow;
      return validateAndReturnExisting(collision.single);
    }

    for (final line in normalizedLines) {
      await db.insert(
        'gl_lines',
        {
          'entry_id': entryId,
          'account_id': line['account_id'],
          'debit': (line['debit'] as num?)?.toDouble() ?? 0,
          'credit': (line['credit'] as num?)?.toDouble() ?? 0,
          'party_type': line['party_type'],
          'party_id': line['party_id'],
          'invoice_id': line['invoice_id'],
          'repair_id': line['repair_id'],
          'cheque_id': line['cheque_id'],
          'created_at': DateTime.now().toIso8601String(),
        },
      );
    }

    await AccountingIntegrityTables.recordPostingEvent(
      db,
      glEntryId: entryId,
      source: canonicalSource,
      sourceId: cleanSourceId,
      canonicalSource: canonicalSource,
      reversalOf: reversalOf,
      actorUserId: actor,
    );

    return entryId;
  }

  // 🎯 إنشاء حسابات العملاء والموردين
  static Future<int> ensureClientAccount(int clientId) async {
    final db = await DBService.database;
    return await _ensureClientAccountOn(db, clientId);
  }

  static Future<int> ensureClientAccountOn(DatabaseExecutor db, int clientId) =>
      _ensureClientAccountOn(db, clientId);

  static Future<int> _ensureClientAccountOn(
      DatabaseExecutor db, int clientId) async {
    final client = await db.query(
      'clients',
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );

    if (client.isEmpty) throw StateError('العميل غير موجود: $clientId');

    final expectedCode = '1200.C$clientId';

    Future<int> validateAccount(Map<String, Object?> row) async {
      if (row['code']?.toString() != expectedCode ||
          row['type']?.toString() != 'ASSET' ||
          row['normal_balance']?.toString() != 'DEBIT') {
        throw StateError(
          'Client $clientId is linked to an invalid AR account. '
          'Expected $expectedCode / ASSET / DEBIT.',
        );
      }

      if (await _accountsHaveCoaMetadata(db)) {
        final active = (row['is_active'] as num?)?.toInt() ?? 1;
        final postable = (row['is_postable'] as num?)?.toInt() ?? 1;
        if (active != 1 || postable != 1) {
          throw StateError(
            'Client AR account $expectedCode is inactive or non-postable.',
          );
        }
      }

      final value = row['id'];
      return value is int ? value : int.parse(value.toString());
    }

    final linkedRaw = client.first['account_id'];
    if (linkedRaw != null) {
      final linkedId =
          linkedRaw is int ? linkedRaw : int.parse(linkedRaw.toString());
      final linked = await db.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [linkedId],
        limit: 1,
      );
      if (linked.isEmpty) {
        throw StateError(
          'Client $clientId points to missing account $linkedId.',
        );
      }
      return validateAccount(linked.first);
    }

    final canonical = await db.query(
      'accounts',
      where: 'code = ?',
      whereArgs: [expectedCode],
      limit: 1,
    );

    late int accountId;
    if (canonical.isNotEmpty) {
      accountId = await validateAccount(canonical.first);
    } else {
      final clientName = client.first['name'] ?? 'عميل $clientId';
      final values = <String, Object?>{
        'code': expectedCode,
        'name': 'عميل: $clientName',
        'type': 'ASSET',
        'normal_balance': 'DEBIT',
        'created_at': DateTime.now().toIso8601String(),
      };

      if (await _accountsHaveCoaMetadata(db)) {
        values.addAll({
          'report_class': 'ASSET',
          'parent_id': await _getAccountIdByCode(db, '1200'),
          'is_postable': 1,
          'is_system': 1,
          'is_active': 1,
          'is_legacy': 0,
        });
      }

      accountId = await SyncFoundationService.writeOn(
          db, (syncTxn) => syncTxn.insert('accounts', values));
    }

    await db.update(
      'clients',
      {'account_id': accountId},
      where: 'id = ?',
      whereArgs: [clientId],
    );

    return accountId;
  }

  static Future<int> ensureSupplierAccount(String supplierId) async {
    final db = await DBService.database;
    return await _ensureSupplierAccountOn(db, supplierId);
  }

  static Future<int> _ensureSupplierAccountOn(
      DatabaseExecutor db, String supplierId) async {
    final raw = supplierId.trim().toUpperCase();
    final numeric = raw.startsWith('S') ? raw.substring(1) : raw;
    final parsed = int.tryParse(numeric);
    if (parsed == null || parsed <= 0) {
      throw StateError('Invalid supplier id: $supplierId');
    }

    final rows = await db.query(
      'suppliers',
      columns: ['id', 'name'],
      where: 'id = ?',
      whereArgs: [parsed],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('المورد غير موجود: $supplierId');
    }

    final code = '2200.S${parsed.toString().padLeft(4, '0')}';
    final existing = await db.query(
      'accounts',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      if (row['type']?.toString() != 'LIABILITY' ||
          row['normal_balance']?.toString() != 'CREDIT') {
        throw StateError(
          'Supplier $parsed account $code has invalid classification.',
        );
      }

      if (await _accountsHaveCoaMetadata(db)) {
        final active = (row['is_active'] as num?)?.toInt() ?? 1;
        final postable = (row['is_postable'] as num?)?.toInt() ?? 1;
        if (active != 1 || postable != 1) {
          throw StateError(
            'Supplier account $code is inactive or non-postable.',
          );
        }
      }

      final value = row['id'];
      return value is int ? value : int.parse(value.toString());
    }

    final values = <String, Object?>{
      'code': code,
      'name': rows.first['name']?.toString() ?? 'مورد $parsed',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT',
      'created_at': DateTime.now().toIso8601String(),
    };

    if (await _accountsHaveCoaMetadata(db)) {
      values.addAll({
        'report_class': 'LIABILITY',
        'parent_id': await _getAccountIdByCode(db, '2200'),
        'is_postable': 1,
        'is_system': 1,
        'is_active': 1,
        'is_legacy': 0,
      });
    }

    return SyncFoundationService.writeOn(
        db, (syncTxn) => syncTxn.insert('accounts', values));
  }

  // 🎯 فاتورة GL
  static Future<int> postInvoiceGLOnTransaction({
    required DatabaseExecutor txn,
    required String invoiceId,
    required DateTime date,
    required int clientId,
    required double total,
    double vatAmount = 0.0,
    String? repairId,
    String? ref,
    String? sourceNumber,
    int postingVersion = 1,
    String? createdBy,
    String? note,
  }) async {
    final arId = await _ensureClientAccountOn(txn, clientId);
    final revenueId = await _getAccountIdByCode(txn, '4000');
    final vatPayableId = await _getAccountIdByCode(txn, '2105');

    if (revenueId == null) throw Exception("حساب الإيرادات 4000 غير موجود");

    final revenuePortion = (total - vatAmount).clamp(0, double.infinity);
    final lines = <Map<String, Object?>>[
      {
        'account_id': arId,
        'debit': total,
        'credit': 0.0,
        'party_type': 'CLIENT',
        'party_id': clientId.toString(),
        'invoice_id': invoiceId,
        'repair_id': repairId,
      },
      {
        'account_id': revenueId,
        'debit': 0.0,
        'credit': revenuePortion,
        'party_type': null,
        'party_id': null,
        'invoice_id': invoiceId,
        'repair_id': repairId,
      },
    ];

    if (vatAmount > 0 && vatPayableId != null) {
      lines.add({
        'account_id': vatPayableId,
        'debit': 0.0,
        'credit': vatAmount,
        'party_type': null,
        'party_id': null,
        'invoice_id': invoiceId,
        'repair_id': repairId,
      });
    }

    final entryId = await _postEntryGLOn(
      db: txn,
      date: date,
      ref: ref ?? invoiceId,
      source: 'INVOICE',
      sourceId: invoiceId,
      sourceNumber: sourceNumber,
      postingVersion: postingVersion,
      createdBy: createdBy,
      note: note ?? 'فاتورة بيع',
      lines: lines,
    );

    // P0.003 — GL is the accounting truth. These invoice fields are only
    // synchronized compatibility/cache fields for old screens and reports.
    await txn.update(
      'invoices',
      {
        'gl_entry_id': entryId,
        'post_to_gl': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [invoiceId],
    );

    return entryId;
  }
  // ======================================================================
  // 🔄 Reverse GL Entry (Cancel / Contra Entry)
  // ======================================================================

  static Future<int> reverseEntryGL(
    int entryId, {
    String? createdBy,
    String? note,
  }) async {
    final db = await DBService.database;
    return SyncFoundationService.transaction(
      db,
      (txn) => reverseEntryGLOn(
        txn,
        entryId,
        createdBy: createdBy,
        note: note,
      ),
    );
  }

  static Future<int> reverseEntryGLOn(
    DatabaseExecutor db,
    int entryId, {
    String? createdBy,
    String? note,
  }) async {
    final head = await db.query(
      'gl_entries',
      where: 'id=?',
      whereArgs: [entryId],
      limit: 1,
    );

    if (head.isEmpty) {
      throw StateError('GL entry $entryId not found');
    }

    final alreadyReversed = await db.query(
      'gl_entries',
      columns: ['id'],
      where: 'reversal_of=?',
      whereArgs: [entryId],
      limit: 1,
    );

    if (alreadyReversed.isNotEmpty) {
      throw StateError(
        'GL entry $entryId is already reversed by '
        'entry ${alreadyReversed.first['id']}.',
      );
    }

    final lines = await db.query(
      'gl_lines',
      where: 'entry_id=?',
      whereArgs: [entryId],
      orderBy: 'id ASC',
    );

    if (lines.isEmpty) {
      throw StateError('GL entry $entryId has no lines');
    }

    final original = head.first;
    final originalRef = original['ref']?.toString().trim();
    final originalSourceNumber = original['source_number']?.toString().trim();

    final reversedLines = <Map<String, Object?>>[
      for (final line in lines)
        {
          'account_id': line['account_id'],
          'debit': (line['credit'] as num).toDouble(),
          'credit': (line['debit'] as num).toDouble(),
          'party_type': line['party_type'],
          'party_id': line['party_id'],
          'invoice_id': line['invoice_id'],
          'repair_id': line['repair_id'],
          'cheque_id': line['cheque_id'],
        },
    ];

    return _postEntryGLOn(
      db: db,
      date: DateTime.now(),
      ref: originalRef == null || originalRef.isEmpty
          ? 'GL-$entryId-REV'
          : '$originalRef-REV',
      source: '${original['source']}_REV',
      sourceId: 'GLREV:$entryId',
      sourceNumber: originalSourceNumber == null || originalSourceNumber.isEmpty
          ? null
          : '$originalSourceNumber-REV',
      postingVersion: 1,
      reversalOf: entryId,
      createdBy: createdBy,
      note: note ?? 'Reverse of GL entry $entryId',
      lines: reversedLines,
    );
  }

  // 🔧 أدوات مساعدة
  static Future<int?> _getAccountIdByCode(
      DatabaseExecutor db, String code) async {
    final result = await db.query(
      'accounts',
      columns: ['id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['id'] as int? : null;
  }

  static Future<void> ensureColumnOn({
    required DatabaseExecutor db,
    required String table,
    required String column,
    required String type,
  }) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => (row['name'] as String?) == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  // 🎯 أضف هذه الدوال المفقودة للتوافق مع db_service.dart
  static Future<int?> getGlEntryIdBySource(
      String source, String sourceId) async {
    final db = await DBService.database;
    final result = await db.query(
      'gl_entries',
      columns: ['id'],
      where: 'source = ? AND source_id = ?',
      whereArgs: [source, sourceId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['id'] as int? : null;
  }

  static Future<int?> getClientIdForRepair(
      DatabaseExecutor txn, String repairId) async {
    final result = await txn.query(
      'repairs',
      columns: ['client_id'],
      where: 'id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['client_id'] as int? : null;
  }

  static Future<bool> columnExists(String table, String column) async {
    final db = await DBService.database;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.any((row) => (row['name'] as String?) == column);
  }

  static Future<int> ensureAccount({
    required String code,
    required String name,
    required String type,
    required String normalBalance,
  }) async {
    final normalizedCode = code.trim();
    final normalizedType = type.trim().toUpperCase();
    final normalizedBalance = normalBalance.trim().toUpperCase();

    if (normalizedCode.isEmpty) {
      throw ArgumentError('Account code is required');
    }

    final expectedBalance = _normalBalanceForType(normalizedType);
    if (normalizedBalance != expectedBalance) {
      throw StateError(
        'Account $normalizedCode normal balance $normalizedBalance '
        'conflicts with type $normalizedType.',
      );
    }

    final db = await DBService.database;
    final result = await db.query(
      'accounts',
      where: 'code = ?',
      whereArgs: [normalizedCode],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final row = result.first;
      if (row['type']?.toString() != normalizedType ||
          row['normal_balance']?.toString() != normalizedBalance) {
        throw StateError(
          'Account $normalizedCode already exists with a conflicting '
          'type/normal balance.',
        );
      }
      return row['id'] as int;
    }

    return SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert('accounts', {
              'code': normalizedCode,
              'name': name,
              'type': normalizedType,
              'normal_balance': normalizedBalance,
              'report_class': _reportClassForType(normalizedType),
              'created_at': DateTime.now().toIso8601String(),
            }));
  }

  static Future<void> ensureDefaultAccountsExist() async {
    final db = await DBService.database;
    await ensureDefaultAccounts(db);
  }

  static Future<void> seedDefaultInsurers(DatabaseExecutor db) async {
    // كود seed insurers
  }

  static Future<int?> accountIdForClient(int clientId) async {
    final db = await DBService.database;
    final result = await db.query(
      'clients',
      columns: ['account_id'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['account_id'] as int? : null;
  }

  static Future<int?> accountIdForSupplier(String supplierId) async {
    final raw = supplierId.trim().toUpperCase();
    final numeric = raw.startsWith('S') ? raw.substring(1) : raw;
    final parsed = int.tryParse(numeric);
    if (parsed == null || parsed <= 0) return null;

    final db = await DBService.database;
    final code = '2200.S${parsed.toString().padLeft(4, '0')}';
    final result = await db.query(
      'accounts',
      columns: ['id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );

    if (result.isEmpty) return null;
    final value = result.first['id'];
    return value is int ? value : int.tryParse(value.toString());
  }

  // 🎯 الدوال المفقودة للتوافق
  static Future<int?> getAccountIdByCode(String code) async {
    final db = await DBService.database;
    final result = await db.query(
      'accounts',
      columns: ['id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['id'] as int? : null;
  }

  static Future<int> postInvoiceGL({
    required String invoiceId,
    required DateTime date,
    required int clientId,
    required double total,
    double vatAmount = 0.0,
    String? repairId,
    String? ref,
    String? sourceNumber,
    int postingVersion = 1,
    String? createdBy,
    String? note,
  }) async {
    final db = await DBService.database;
    return SyncFoundationService.transaction(
      db,
      (txn) => postInvoiceGLOnTransaction(
        txn: txn,
        invoiceId: invoiceId,
        date: date,
        clientId: clientId,
        total: total,
        vatAmount: vatAmount,
        repairId: repairId,
        ref: ref,
        sourceNumber: sourceNumber,
        postingVersion: postingVersion,
        createdBy: createdBy,
        note: note,
      ),
    );
  }

  static Future<void> ensureColumn({
    required String table,
    required String column,
    required String type,
  }) async {
    final db = await DBService.database;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => (row['name'] as String?) == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  static Future<int> postRepairGL({
    required DatabaseExecutor txn,
    required String repairId,
    required int clientId,
    required double fileValue,
    DateTime? date,
  }) async {
    // كود postRepairGL الأساسي
    date ??= DateTime.now();
    final arId = await _ensureClientAccountOn(txn, clientId);
    final revenueId = await _getAccountIdByCode(txn, '4000');

    if (revenueId == null) {
      throw Exception("حساب الإيرادات 4000 غير موجود");
    }

    final lines = <Map<String, Object?>>[
      {
        'account_id': arId,
        'debit': fileValue,
        'credit': 0.0,
        'party_type': 'CLIENT',
        'party_id': clientId.toString(),
        'repair_id': repairId,
      },
      {
        'account_id': revenueId,
        'debit': 0.0,
        'credit': fileValue,
        'party_type': null,
        'party_id': null,
        'repair_id': repairId,
      },
    ];

    return await _postEntryGLOn(
      db: txn,
      date: date,
      ref: "REPAIR-$repairId",
      source: 'REPAIR_OPEN',
      sourceId: repairId,
      note: 'Opening Repair File',
      lines: lines,
    );
  }

  static Future<int> postEmployeeAdvanceGL({
    required String employeeId,
    required DateTime date,
    required double amount,
    required bool viaBank,
    String? ref,
    String? sourceNumber,
    int postingVersion = 1,
    String? createdBy,
    String? note,
  }) async {
    final db = await DBService.database;
    final advSubId = await ensureEmployeeAdvanceSubAccount(employeeId);
    final cashOrBankId =
        await _getAccountIdByCode(db, viaBank ? '1010' : '1000');

    final lines = <Map<String, Object?>>[
      {
        'account_id': advSubId,
        'debit': amount,
        'credit': 0.0,
        'party_type': 'EMPLOYEE',
        'party_id': employeeId,
      },
      {
        'account_id': cashOrBankId!,
        'debit': 0.0,
        'credit': amount,
        'party_type': null,
        'party_id': null,
      },
    ];

    final srcId = 'EMPADV-$employeeId-${date.toIso8601String()}';
    return await _postEntryGLOn(
      db: db,
      date: date,
      ref: ref,
      source: 'EMP_ADV',
      sourceId: srcId,
      sourceNumber: sourceNumber,
      postingVersion: postingVersion,
      createdBy: createdBy,
      note: note,
      lines: lines,
    );
  }

  static Future<int> ensureEmployeeAdvanceSubAccount(String employeeId) async {
    final db = await DBService.database;
    await _getAccountIdByCode(db, '1120');
    final code = '1120.E$employeeId';
    final result = await db.query('accounts',
        where: 'code=?', whereArgs: [code], limit: 1);
    if (result.isNotEmpty) return result.first['id'] as int;

    return await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert('accounts', {
              'code': code,
              'name': 'سلف موظف - $employeeId',
              'type': 'ASSET',
              'normal_balance': 'DEBIT',
            }));
  }

// ============================================================
// 🎯 نشر قيد دفعة شراء PURCHASE_PAY
// ============================================================
  static Future<int> postPurchasePaymentGL({
    required String paymentId,
    required DateTime date,
    required String supplierId,
    required double amount,
    required bool viaBank,
    String? ref,
    String? note,
  }) async {
    final db = await DBService.database;

    // 1) حسابات رئيسية
    final cashId = await _getAccountIdByCode(db, '1000'); // الصندوق
    final bankId = await _getAccountIdByCode(db, '1010'); // البنك
    final apRootId = await _getAccountIdByCode(db, '2200'); // ذمم الموردين

    if (cashId == null || bankId == null || apRootId == null) {
      throw StateError('الحسابات الأساسية غير متوفرة.');
    }

    // 2) P0.005 — canonical supplier AP is always 2200.S####.
    // supplierId is suppliers.id, not a PID/account-code fragment.
    final supAccId = await _ensureSupplierAccountOn(db, supplierId);

    // 3) قيود اليومية
    final debitLine = {
      'account_id': supAccId,
      'debit': amount,
      'credit': 0.0,
      'party_type': 'SUPPLIER',
      'party_id': supplierId,
    };

    final creditLine = {
      'account_id': viaBank ? bankId : cashId,
      'debit': 0.0,
      'credit': amount,
      'party_type': null,
      'party_id': null,
    };

    // 4) نشر القيد
    final entryId = await _postEntryGLOn(
      db: db,
      date: date,
      ref: ref ?? paymentId,
      source: 'PURCHASE_PAY',
      sourceId: paymentId,
      note: note ?? 'Purchase Payment',
      lines: [debitLine, creditLine],
    );

    return entryId;
  }

  // ======================================================================
// 🔄 Reverse Repair GL (Replacement for DBService.reverseRepairGL)
// ======================================================================
  static Future<int> reverseRepairGL({
    required DatabaseExecutor txn,
    required String repairId,
    required double oldValue,
    required int clientId,
    DateTime? date,
    String? note,
  }) async {
    date ??= DateTime.now();

    // 1) الحصول على حساب العميل
    final arId = await _ensureClientAccountOn(txn, clientId);

    // 2) حساب الإيرادات 4000
    final revenueId = await _getAccountIdByCode(txn, '4000');
    if (revenueId == null) {
      throw Exception("حساب الإيرادات 4000 غير موجود");
    }

    // 3) قيود عكسية بالقيمة القديمة
    final List<Map<String, Object?>> lines = [
      {
        'account_id': arId,
        'debit': 0.0,
        'credit': oldValue,
        'party_type': 'CLIENT',
        'party_id': clientId.toString(),
        'repair_id': repairId,
      },
      {
        'account_id': revenueId,
        'debit': oldValue,
        'credit': 0.0,
        'party_type': null,
        'party_id': null,
        'repair_id': repairId,
      },
    ];

    return await _postEntryGLOn(
      db: txn,
      date: date,
      ref: "REPAIR-$repairId-REV",
      source: 'REPAIR_REV',
      sourceId: repairId,
      note: note ?? "Reversal of Repair File",
      lines: lines,
    );
  }

// // ======================================================================
// 🆙 Adjust Repair GL — النسخة الجديدة المعتمدة على "diff"
// ======================================================================
  static Future<int> adjustRepairGL({
    required DatabaseExecutor txn,
    required String repairId,
    required double diff, // القيمة الفرقية فقط
    required int clientId,
    DateTime? date,
    String? note,
  }) async {
    date ??= DateTime.now();

    // إذا الفرق = صفر → لا نُسجل أي قيد
    if (diff.abs() < 0.01) {
      return 0;
    }

    // 1) حساب العميل (ذمم العملاء)
    final arId = await _ensureClientAccountOn(txn, clientId);

    // 2) حساب الإيرادات
    final revenueId = await _getAccountIdByCode(txn, '4000');
    if (revenueId == null) {
      throw Exception("حساب الإيرادات 4000 غير موجود");
    }

    // 3) إذا diff موجب → زيادة قيمة الملف
    if (diff > 0) {
      final List<Map<String, Object?>> lines = [
        {
          'account_id': arId,
          'debit': diff,
          'credit': 0.0,
          'party_type': 'CLIENT',
          'party_id': clientId.toString(),
          'repair_id': repairId,
        },
        {
          'account_id': revenueId,
          'debit': 0.0,
          'credit': diff,
          'party_type': null,
          'party_id': null,
          'repair_id': repairId,
        },
      ];

      return await _postEntryGLOn(
        db: txn,
        date: date,
        ref: "REPAIR-$repairId-ADJ",
        source: 'REPAIR_ADJ',
        sourceId: repairId,
        note: note ?? "Adjustment (Increase)",
        lines: lines,
      );
    }

    // 4) إذا diff سالب → تخفيض قيمة الملف
    final double absDiff = diff.abs();

    final List<Map<String, Object?>> lines = [
      {
        'account_id': arId,
        'debit': 0.0,
        'credit': absDiff,
        'party_type': 'CLIENT',
        'party_id': clientId.toString(),
        'repair_id': repairId,
      },
      {
        'account_id': revenueId,
        'debit': absDiff,
        'credit': 0.0,
        'party_type': null,
        'party_id': null,
        'repair_id': repairId,
      },
    ];

    return await _postEntryGLOn(
      db: txn,
      date: date,
      ref: "REPAIR-$repairId-ADJ",
      source: 'REPAIR_ADJ',
      sourceId: repairId,
      note: note ?? "Adjustment (Decrease)",
      lines: lines,
    );
  }

  // ======================================================================
// 🎯 A — postInvoiceGLFromId (Centralized Invoice Posting)
// ======================================================================
  static Future<int> postInvoiceGLFromId(
    String invoiceId, {
    String? createdBy,
  }) async {
    final db = await DBService.database;

    // 1) اجلب الفاتورة
    final inv = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );

    if (inv.isEmpty) {
      throw StateError("Invoice not found: $invoiceId");
    }

    final row = inv.first;

    // 2) استخراج البيانات اللازمة
    final clientId = row['client_id'] as int?;
    final repairId = row['repair_id']?.toString();
    final total = (row['total'] as num?)?.toDouble() ?? 0.0;
    final vat = (row['vat'] as num?)?.toDouble() ?? 0.0;
    final dateStr = row['date']?.toString();
    final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();

    if (clientId == null) {
      throw StateError("Invoice $invoiceId has no client_id");
    }

    // 3) حسابات الإيرادات والضريبة من داخل الجداول
    final arId = await _ensureClientAccountOn(db, clientId);
    final revenueId = await _getAccountIdByCode(db, '4000');
    final vatPayId = await _getAccountIdByCode(db, '2105');

    if (revenueId == null) {
      throw StateError("Revenue account 4000 is missing");
    }

    final revenuePortion = (total - vat).clamp(0, double.infinity);

    // 4) بناء بنود القيد
    final lines = <Map<String, Object?>>[
      {
        'account_id': arId,
        'debit': total,
        'credit': 0.0,
        'party_type': 'CLIENT',
        'party_id': clientId.toString(),
        'invoice_id': invoiceId,
        'repair_id': repairId,
      },
      {
        'account_id': revenueId,
        'debit': 0.0,
        'credit': revenuePortion,
        'party_type': null,
        'party_id': null,
        'invoice_id': invoiceId,
        'repair_id': repairId,
      },
    ];

    if (vat > 0 && vatPayId != null) {
      lines.add({
        'account_id': vatPayId,
        'debit': 0.0,
        'credit': vat,
        'invoice_id': invoiceId,
        'repair_id': repairId,
      });
    }

    // 5) نشر القيد
    final entryId = await _postEntryGLOn(
      db: db,
      date: date,
      ref: invoiceId,
      source: 'INVOICE',
      sourceId: invoiceId,
      sourceNumber: row['document_number']?.toString(),
      createdBy: createdBy,
      note: 'فاتورة بيع',
      lines: lines,
    );
// ربط قيد GL مع الفاتورة
    await db.update(
      'invoices',
      {
        'gl_entry_id': entryId,
        'post_to_gl': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [invoiceId],
    );

    return entryId;
  }
}
