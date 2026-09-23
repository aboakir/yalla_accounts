// -----------------------------------------------------------------------------
// lib/core/services/db/tables/cheque_tables.dart
// P0.008 — canonical cheque schema / lifecycle support
// -----------------------------------------------------------------------------

import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class ChequeTables {
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createChequeTable(db);
    await ensureChequesSchema(db);
  }

  static Future<void> _createChequeTable(DatabaseExecutor db) async {
    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheques (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT,
        cheque_no TEXT,
        cheque_type TEXT NOT NULL DEFAULT 'incoming',
        status TEXT NOT NULL DEFAULT 'pending',
        drawer_name TEXT,
        bank_name TEXT,
        bank_branch TEXT,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'ILS',
        issue_date TEXT,
        due_date TEXT,
        source_type TEXT,
        source_id TEXT,
        supplier_pid TEXT,
        client_id INTEGER,
        recipient_type TEXT,
        recipient_id TEXT,
        recipient_name TEXT,
        linked_payment_ids TEXT,
        linked_repair_ids TEXT,
        gl_entry_id INTEGER,
        notes TEXT,
        origin_cheque_id TEXT,
        is_endorsed INTEGER NOT NULL DEFAULT 0,
        endorsed_at TEXT,
        last_endorser_name TEXT,
        auto_return_date TEXT,
        return_reason TEXT,
        is_legacy_incomplete INTEGER NOT NULL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,

        -- Compatibility aliases for old code/data.
        supplier_id INTEGER,
        payment_id TEXT,
        date TEXT,
        bank TEXT,
        number TEXT
      )
    ''');
  }

  static Future<void> ensureChequesSchema(DatabaseExecutor db) async {
    await _createChequeTable(db);

    final columns = <String, String>{
      'uuid': 'TEXT',
      'cheque_no': 'TEXT',
      'cheque_type': "TEXT NOT NULL DEFAULT 'incoming'",
      'status': "TEXT NOT NULL DEFAULT 'pending'",
      'drawer_name': 'TEXT',
      'bank_name': 'TEXT',
      'bank_branch': 'TEXT',
      'currency': "TEXT NOT NULL DEFAULT 'ILS'",
      'issue_date': 'TEXT',
      'due_date': 'TEXT',
      'source_type': 'TEXT',
      'source_id': 'TEXT',
      'supplier_pid': 'TEXT',
      'client_id': 'INTEGER',
      'recipient_type': 'TEXT',
      'recipient_id': 'TEXT',
      'recipient_name': 'TEXT',
      'linked_payment_ids': 'TEXT',
      'linked_repair_ids': 'TEXT',
      'gl_entry_id': 'INTEGER',
      'notes': 'TEXT',
      'origin_cheque_id': 'TEXT',
      'is_endorsed': 'INTEGER NOT NULL DEFAULT 0',
      'endorsed_at': 'TEXT',
      'last_endorser_name': 'TEXT',
      'auto_return_date': 'TEXT',
      'return_reason': 'TEXT',
      'is_legacy_incomplete': 'INTEGER NOT NULL DEFAULT 0',
      'direction': 'TEXT',
      'instrument_key': 'TEXT',
      'receipt_voucher_id': 'INTEGER',
      'payment_voucher_id': 'TEXT',
      'source_party_type': 'TEXT',
      'source_party_id': 'TEXT',
      'bank_account_id': 'INTEGER',
      'cheque_book_id': 'TEXT',
      'created_by': 'TEXT',
      'deposited_at': 'TEXT',
      'collection_date': 'TEXT',
      'delivered_at': 'TEXT',
      'presented_at': 'TEXT',
      'cleared_at': 'TEXT',
      'returned_at': 'TEXT',
      'cancelled_at': 'TEXT',
      'cancelled_by': 'TEXT',
      'cancellation_reason': 'TEXT',
      'created_at': 'TEXT',
      'updated_at': 'TEXT',
      'supplier_id': 'INTEGER',
      'payment_id': 'TEXT',
      'date': 'TEXT',
      'bank': 'TEXT',
      'number': 'TEXT',
    };

    for (final entry in columns.entries) {
      await _ensureColumn(db, 'cheques', entry.key, entry.value);
    }

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheque_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cheque_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        from_status TEXT,
        to_status TEXT,
        event_date TEXT NOT NULL,
        gl_entry_id INTEGER,
        actor_user_id TEXT,
        reason TEXT,
        metadata_json TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await _ensureColumn(db, 'cheque_events', 'actor_user_id', 'TEXT');
    await _ensureColumn(db, 'cheque_events', 'reason', 'TEXT');
    await _ensureColumn(db, 'cheque_events', 'metadata_json', 'TEXT');

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheque_voucher_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cheque_id INTEGER NOT NULL,
        voucher_type TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        instrument_key TEXT NOT NULL,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        CHECK(amount > 0),
        CHECK(voucher_type IN ('RECEIPT','PAYMENT')),
        UNIQUE(cheque_id),
        UNIQUE(voucher_type, voucher_id, instrument_key)
      )
    ''');

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheque_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cheque_id INTEGER NOT NULL,
        voucher_type TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        allocation_type TEXT NOT NULL,
        target_id TEXT,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        CHECK(amount > 0),
        CHECK(voucher_type IN ('RECEIPT','PAYMENT')),
        UNIQUE(
          cheque_id,
          voucher_type,
          voucher_id,
          allocation_type,
          target_id
        )
      )
    ''');

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheque_books (
        id TEXT PRIMARY KEY,
        bank_account_id INTEGER NOT NULL,
        book_number TEXT NOT NULL,
        first_cheque_number INTEGER NOT NULL,
        last_cheque_number INTEGER NOT NULL,
        next_available_number INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'OPEN',
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK(first_cheque_number > 0),
        CHECK(last_cheque_number >= first_cheque_number),
        CHECK(next_available_number >= first_cheque_number),
        CHECK(next_available_number <= last_cheque_number + 1),
        CHECK(status IN ('OPEN','CLOSED','EXHAUSTED')),
        UNIQUE(bank_account_id, book_number)
      )
    ''');

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheque_deposit_batches (
        id TEXT PRIMARY KEY,
        bank_account_id INTEGER NOT NULL,
        deposit_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'DEPOSITED',
        cheque_count INTEGER NOT NULL DEFAULT 0,
        total_value REAL NOT NULL DEFAULT 0,
        notes TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        CHECK(cheque_count >= 0),
        CHECK(total_value >= 0),
        CHECK(status IN ('DEPOSITED','CANCELLED'))
      )
    ''');

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheque_deposit_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id TEXT NOT NULL,
        cheque_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        CHECK(amount > 0),
        UNIQUE(cheque_id),
        UNIQUE(batch_id, cheque_id)
      )
    ''');

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheque_endorsements (
        id TEXT PRIMARY KEY,
        cheque_id INTEGER NOT NULL,
        sequence_no INTEGER NOT NULL,
        from_party_type TEXT,
        from_party_id TEXT,
        from_party_name TEXT,
        to_party_type TEXT NOT NULL,
        to_party_id TEXT,
        to_party_name TEXT NOT NULL,
        amount REAL NOT NULL,
        purpose TEXT,
        source_obligation_type TEXT,
        source_obligation_id TEXT,
        event_date TEXT NOT NULL,
        created_by TEXT,
        created_at TEXT NOT NULL,
        CHECK(sequence_no > 0),
        CHECK(amount > 0),
        UNIQUE(cheque_id, sequence_no)
      )
    ''');

    // Normalize legacy aliases. Never invent missing cheque metadata.
    await db.execute(r'''
      UPDATE cheques
      SET uuid = COALESCE(NULLIF(uuid,''), 'legacy-cheque-' || id),
          cheque_no = COALESCE(NULLIF(cheque_no,''), number, ''),
          bank_name = COALESCE(NULLIF(bank_name,''), bank, ''),
          issue_date = COALESCE(NULLIF(issue_date,''), date, due_date),
          supplier_pid = COALESCE(
            NULLIF(supplier_pid,''),
            CASE WHEN supplier_id IS NULL THEN NULL
                 ELSE CAST(supplier_id AS TEXT) END
          ),
          source_type = COALESCE(
            NULLIF(source_type,''),
            CASE WHEN payment_id IS NULL OR TRIM(payment_id)=''
                 THEN NULL ELSE 'PAYMENT' END
          ),
          source_id = COALESCE(NULLIF(source_id,''), payment_id),
          cheque_type = CASE
            WHEN supplier_id IS NOT NULL THEN 'outgoing'
            WHEN cheque_type IS NULL OR TRIM(cheque_type)='' THEN 'incoming'
            ELSE cheque_type
          END,
          currency = COALESCE(NULLIF(currency,''), 'ILS'),
          direction = COALESCE(
            NULLIF(direction,''),
            CASE
              WHEN cheque_type='outgoing' THEN 'ISSUED'
              ELSE 'RECEIVED'
            END
          ),
          status = CASE
            WHEN LOWER(COALESCE(status,''))='pending'
              AND cheque_type='outgoing' THEN 'issued'
            WHEN LOWER(COALESCE(status,''))='pending'
              THEN 'received'
            ELSE status
          END,
          instrument_key = COALESCE(
            NULLIF(instrument_key,''),
            NULLIF(uuid,''),
            'legacy-cheque-' || id
          ),
          payment_voucher_id = COALESCE(
            NULLIF(payment_voucher_id,''),
            CASE
              WHEN UPPER(COALESCE(source_type,''))='VOUCHER'
              THEN source_id ELSE NULL
            END
          ),
          receipt_voucher_id = receipt_voucher_id,
          source_party_type = COALESCE(
            NULLIF(source_party_type,''),
            CASE
              WHEN client_id IS NOT NULL THEN 'CLIENT'
              WHEN supplier_pid IS NOT NULL AND TRIM(supplier_pid)<>'' THEN 'SUPPLIER'
              WHEN recipient_type IS NOT NULL AND TRIM(recipient_type)<>'' THEN recipient_type
              ELSE NULL
            END
          ),
          source_party_id = COALESCE(
            NULLIF(source_party_id,''),
            CASE
              WHEN client_id IS NOT NULL THEN CAST(client_id AS TEXT)
              WHEN supplier_pid IS NOT NULL AND TRIM(supplier_pid)<>'' THEN supplier_pid
              WHEN recipient_id IS NOT NULL AND TRIM(recipient_id)<>'' THEN recipient_id
              ELSE NULL
            END
          ),
          is_legacy_incomplete = CASE
            WHEN COALESCE(NULLIF(cheque_no,''), NULLIF(number,''), '')=''
              OR COALESCE(NULLIF(bank_name,''), NULLIF(bank,''), '')=''
              OR COALESCE(NULLIF(drawer_name,''), '')=''
            THEN 1 ELSE COALESCE(is_legacy_incomplete,0)
          END,
          created_at = COALESCE(created_at, datetime('now')),
          updated_at = COALESCE(updated_at, datetime('now'))
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_status ON cheques(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_due_date ON cheques(due_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_client ON cheques(client_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_supplier_pid '
      'ON cheques(supplier_pid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_source '
      'ON cheques(source_type, source_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheque_events_cheque '
      'ON cheque_events(cheque_id, id)',
    );
    await db.execute(r'''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_cheques_uuid
      ON cheques(uuid)
      WHERE uuid IS NOT NULL AND TRIM(uuid) <> ''
    ''');
    await db.execute('DROP INDEX IF EXISTS uq_cheques_source');
    await db.execute(r'''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_cheques_source_instrument
      ON cheques(source_type, source_id, instrument_key)
      WHERE source_type IS NOT NULL
        AND TRIM(source_type) <> ''
        AND source_id IS NOT NULL
        AND TRIM(source_id) <> ''
        AND instrument_key IS NOT NULL
        AND TRIM(instrument_key) <> ''
    ''');
    await db.execute(r'''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_cheques_book_number
      ON cheques(cheque_book_id, cheque_no)
      WHERE cheque_book_id IS NOT NULL
        AND TRIM(cheque_book_id) <> ''
        AND cheque_no IS NOT NULL
        AND TRIM(cheque_no) <> ''
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheque_voucher_links_voucher '
      'ON cheque_voucher_links(voucher_type, voucher_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheque_allocations_target '
      'ON cheque_allocations(allocation_type, target_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheque_deposit_items_batch '
      'ON cheque_deposit_items(batch_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheque_endorsements_cheque '
      'ON cheque_endorsements(cheque_id, sequence_no)',
    );

    await _installCanonicalTriggers(db);
    await _backfillCanonicalLinks(db);
    await _ensureChequeAccounts(db);
  }

  static Future<void> _installCanonicalTriggers(DatabaseExecutor db) async {
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheques_material_insert
      BEFORE INSERT ON cheques
      WHEN COALESCE(NEW.is_legacy_incomplete,0)=0
      BEGIN
        SELECT CASE
          WHEN COALESCE(NEW.amount,0) <= 0
          THEN RAISE(ABORT, 'CHEQUE_AMOUNT_MUST_BE_POSITIVE')
        END;
        SELECT CASE
          WHEN TRIM(COALESCE(NEW.cheque_no,''))=''
          THEN RAISE(ABORT, 'CHEQUE_NUMBER_REQUIRED')
        END;
        SELECT CASE
          WHEN UPPER(COALESCE(NEW.direction,'')) NOT IN ('RECEIVED','ISSUED')
          THEN RAISE(ABORT, 'CHEQUE_DIRECTION_INVALID')
        END;
        SELECT CASE
          WHEN UPPER(COALESCE(NEW.direction,''))='RECEIVED'
            AND TRIM(COALESCE(NEW.drawer_name,''))=''
          THEN RAISE(ABORT, 'RECEIVED_CHEQUE_DRAWER_REQUIRED')
        END;
        SELECT CASE
          WHEN UPPER(COALESCE(NEW.direction,''))='ISSUED'
            AND TRIM(COALESCE(NEW.recipient_name,''))=''
          THEN RAISE(ABORT, 'ISSUED_CHEQUE_PAYEE_REQUIRED')
        END;
        SELECT CASE
          WHEN UPPER(COALESCE(NEW.direction,''))='ISSUED'
            AND NEW.bank_account_id IS NULL
          THEN RAISE(ABORT, 'ISSUED_CHEQUE_BANK_ACCOUNT_REQUIRED')
        END;
      END
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheques_material_update
      BEFORE UPDATE OF amount,cheque_no,direction,drawer_name,recipient_name,
        bank_account_id ON cheques
      WHEN COALESCE(NEW.is_legacy_incomplete,0)=0
      BEGIN
        SELECT CASE
          WHEN COALESCE(NEW.amount,0) <= 0
          THEN RAISE(ABORT, 'CHEQUE_AMOUNT_MUST_BE_POSITIVE')
        END;
        SELECT CASE
          WHEN TRIM(COALESCE(NEW.cheque_no,''))=''
          THEN RAISE(ABORT, 'CHEQUE_NUMBER_REQUIRED')
        END;
        SELECT CASE
          WHEN UPPER(COALESCE(NEW.direction,'')) NOT IN ('RECEIVED','ISSUED')
          THEN RAISE(ABORT, 'CHEQUE_DIRECTION_INVALID')
        END;
        SELECT CASE
          WHEN UPPER(COALESCE(NEW.direction,''))='RECEIVED'
            AND TRIM(COALESCE(NEW.drawer_name,''))=''
          THEN RAISE(ABORT, 'RECEIVED_CHEQUE_DRAWER_REQUIRED')
        END;
        SELECT CASE
          WHEN UPPER(COALESCE(NEW.direction,''))='ISSUED'
            AND TRIM(COALESCE(NEW.recipient_name,''))=''
          THEN RAISE(ABORT, 'ISSUED_CHEQUE_PAYEE_REQUIRED')
        END;
        SELECT CASE
          WHEN UPPER(COALESCE(NEW.direction,''))='ISSUED'
            AND NEW.bank_account_id IS NULL
          THEN RAISE(ABORT, 'ISSUED_CHEQUE_BANK_ACCOUNT_REQUIRED')
        END;
      END
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_voucher_link_insert
      BEFORE INSERT ON cheque_voucher_links
      BEGIN
        SELECT CASE
          WHEN NEW.voucher_type='RECEIPT'
            AND UPPER(COALESCE((SELECT direction FROM cheques WHERE id=NEW.cheque_id),''))<>'RECEIVED'
          THEN RAISE(ABORT, 'RECEIPT_CHEQUE_DIRECTION_MISMATCH')
        END;
        SELECT CASE
          WHEN NEW.voucher_type='PAYMENT'
            AND UPPER(COALESCE((SELECT direction FROM cheques WHERE id=NEW.cheque_id),''))<>'ISSUED'
          THEN RAISE(ABORT, 'PAYMENT_CHEQUE_DIRECTION_MISMATCH')
        END;
        SELECT CASE
          WHEN ABS(
            NEW.amount - COALESCE((SELECT amount FROM cheques WHERE id=NEW.cheque_id),-1)
          ) > 0.005
          THEN RAISE(ABORT, 'CHEQUE_VOUCHER_AMOUNT_MISMATCH')
        END;
      END
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_voucher_links_no_update
      BEFORE UPDATE ON cheque_voucher_links
      BEGIN
        SELECT RAISE(ABORT, 'CHEQUE_VOUCHER_LINK_IMMUTABLE');
      END
    ''');
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_voucher_links_no_delete
      BEFORE DELETE ON cheque_voucher_links
      BEGIN
        SELECT RAISE(ABORT, 'CHEQUE_VOUCHER_LINK_IMMUTABLE');
      END
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_events_no_update
      BEFORE UPDATE ON cheque_events
      BEGIN
        SELECT RAISE(ABORT, 'CHEQUE_HISTORY_IMMUTABLE');
      END
    ''');
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_events_no_delete
      BEFORE DELETE ON cheque_events
      BEGIN
        SELECT RAISE(ABORT, 'CHEQUE_HISTORY_IMMUTABLE');
      END
    ''');
    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_allocations_no_delete
      BEFORE DELETE ON cheque_allocations
      BEGIN
        SELECT RAISE(ABORT, 'CHEQUE_ALLOCATION_HISTORY_IMMUTABLE');
      END
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_voucher_link_insert
      BEFORE INSERT ON cheque_voucher_links
      BEGIN
        SELECT CASE
          WHEN NOT EXISTS(
            SELECT 1 FROM cheques c WHERE c.id=NEW.cheque_id
          )
          THEN RAISE(ABORT, 'CHEQUE_LINK_CHEQUE_NOT_FOUND')
        END;
        SELECT CASE
          WHEN ABS(
            COALESCE((SELECT c.amount FROM cheques c WHERE c.id=NEW.cheque_id),0)
            - NEW.amount
          ) > 0.005
          THEN RAISE(ABORT, 'CHEQUE_LINK_AMOUNT_MISMATCH')
        END;
        SELECT CASE
          WHEN NEW.voucher_type='RECEIPT'
            AND UPPER(COALESCE((
              SELECT c.direction FROM cheques c WHERE c.id=NEW.cheque_id
            ),''))<>'RECEIVED'
          THEN RAISE(ABORT, 'CHEQUE_RECEIPT_DIRECTION_MISMATCH')
        END;
        SELECT CASE
          WHEN NEW.voucher_type='PAYMENT'
            AND UPPER(COALESCE((
              SELECT c.direction FROM cheques c WHERE c.id=NEW.cheque_id
            ),''))<>'ISSUED'
          THEN RAISE(ABORT, 'CHEQUE_PAYMENT_DIRECTION_MISMATCH')
        END;

      END
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_allocation_insert_cap
      BEFORE INSERT ON cheque_allocations
      BEGIN
        SELECT CASE
          WHEN (
            COALESCE((
              SELECT SUM(a.amount)
              FROM cheque_allocations a
              WHERE a.cheque_id=NEW.cheque_id
            ),0) + NEW.amount
          ) > COALESCE((
            SELECT c.amount FROM cheques c WHERE c.id=NEW.cheque_id
          ),0) + 0.005
          THEN RAISE(ABORT, 'CHEQUE_ALLOCATION_EXCEEDS_AMOUNT')
        END;
      END
    ''');

    await db.execute(r'''
      CREATE TRIGGER IF NOT EXISTS trg_cheque_allocation_update_cap
      BEFORE UPDATE OF amount,cheque_id ON cheque_allocations
      BEGIN
        SELECT CASE
          WHEN (
            COALESCE((
              SELECT SUM(a.amount)
              FROM cheque_allocations a
              WHERE a.cheque_id=NEW.cheque_id AND a.id<>OLD.id
            ),0) + NEW.amount
          ) > COALESCE((
            SELECT c.amount FROM cheques c WHERE c.id=NEW.cheque_id
          ),0) + 0.005
          THEN RAISE(ABORT, 'CHEQUE_ALLOCATION_EXCEEDS_AMOUNT')
        END;
      END
    ''');
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<void> _backfillCanonicalLinks(DatabaseExecutor db) async {
    final hasPayments = await _tableExists(db, 'payments');
    final hasVouchers = await _tableExists(db, 'vouchers');

    if (hasPayments) {
      await db.execute(r'''
        UPDATE cheques
        SET receipt_voucher_id = (
          SELECT p.receipt_number
          FROM payments p
          WHERE p.id=cheques.source_id
            AND p.receipt_number IS NOT NULL
          LIMIT 1
        )
        WHERE receipt_voucher_id IS NULL
          AND UPPER(COALESCE(source_type,''))='PAYMENT'
      ''');

      await db.execute(r'''
        INSERT OR IGNORE INTO cheque_voucher_links(
          cheque_id,voucher_type,voucher_id,instrument_key,amount,created_at
        )
        SELECT
          c.id,
          'RECEIPT',
          CAST(p.receipt_number AS TEXT),
          COALESCE(NULLIF(c.instrument_key,''), c.uuid, 'legacy-' || c.id),
          c.amount,
          COALESCE(c.created_at,datetime('now'))
        FROM cheques c
        JOIN payments p ON p.id=c.source_id
        WHERE UPPER(COALESCE(c.source_type,''))='PAYMENT'
          AND p.receipt_number IS NOT NULL
      ''');

      await db.execute(r'''
        INSERT OR IGNORE INTO cheque_allocations(
          cheque_id,voucher_type,voucher_id,allocation_type,target_id,
          amount,created_at
        )
        SELECT
          c.id,
          'RECEIPT',
          CAST(p.receipt_number AS TEXT),
          CASE
            WHEN COALESCE(NULLIF(p.repair_id,''),NULLIF(p.relatedRepairId,'')) IS NULL
            THEN 'CREDIT'
            ELSE 'REPAIR'
          END,
          COALESCE(NULLIF(p.repair_id,''),NULLIF(p.relatedRepairId,''),''),
          p.amount,
          COALESCE(c.created_at,datetime('now'))
        FROM cheques c
        JOIN payments p ON p.id=c.source_id
        WHERE UPPER(COALESCE(c.source_type,''))='PAYMENT'
          AND NOT EXISTS(
            SELECT 1 FROM cheque_allocations a
            WHERE a.cheque_id=c.id
          )
      ''');
    }

    if (hasVouchers) {
      await db.execute(r'''
        UPDATE cheques
        SET payment_voucher_id=source_id
        WHERE payment_voucher_id IS NULL
          AND UPPER(COALESCE(source_type,''))='VOUCHER'
      ''');

      await db.execute(r'''
        INSERT OR IGNORE INTO cheque_voucher_links(
          cheque_id,voucher_type,voucher_id,instrument_key,amount,created_at
        )
        SELECT
          c.id,
          'PAYMENT',
          c.source_id,
          COALESCE(NULLIF(c.instrument_key,''), c.uuid, 'legacy-' || c.id),
          c.amount,
          COALESCE(c.created_at,datetime('now'))
        FROM cheques c
        WHERE UPPER(COALESCE(c.source_type,''))='VOUCHER'
          AND TRIM(COALESCE(c.source_id,''))<>''
      ''');

      await db.execute(r'''
        INSERT OR IGNORE INTO cheque_allocations(
          cheque_id,voucher_type,voucher_id,allocation_type,target_id,
          amount,created_at
        )
        SELECT
          c.id,
          'PAYMENT',
          v.id,
          CASE
            WHEN UPPER(COALESCE(v.party_type,''))='SUPPLIER'
                 AND TRIM(COALESCE(v.reference,''))<>'' THEN 'PURCHASE_INVOICE'
            WHEN UPPER(COALESCE(v.source,''))='PAYROLL_ENTITLEMENT'
                 THEN 'PAYROLL'
            WHEN UPPER(COALESCE(v.party_type,''))='SUPPLIER'
                 THEN 'PARTY_ACCOUNT'
            ELSE 'EXPENSE'
          END,
          CASE
            WHEN UPPER(COALESCE(v.party_type,''))='SUPPLIER'
                 AND TRIM(COALESCE(v.reference,''))<>'' THEN v.reference
            WHEN UPPER(COALESCE(v.source,''))='PAYROLL_ENTITLEMENT'
                 AND TRIM(COALESCE(v.source_id,''))<>'' THEN v.source_id
            WHEN UPPER(COALESCE(v.party_type,''))='SUPPLIER'
                 THEN COALESCE(v.party_id,'')
            WHEN TRIM(COALESCE(v.source_id,''))<>'' THEN v.source_id
            ELSE COALESCE(v.party_id,'')
          END,
          c.amount,
          COALESCE(c.created_at,datetime('now'))
        FROM cheques c
        JOIN vouchers v ON v.id=c.source_id
        WHERE UPPER(COALESCE(c.source_type,''))='VOUCHER'
          AND NOT EXISTS(
            SELECT 1 FROM cheque_allocations a
            WHERE a.cheque_id=c.id
          )
      ''');
    }

    final hasReceiptHeaders = await _tableExists(db, 'receipt_headers');
    if (hasReceiptHeaders) {
      await db.execute(r'''
        CREATE TRIGGER IF NOT EXISTS trg_cheque_receipt_link_exists
        BEFORE INSERT ON cheque_voucher_links
        WHEN NEW.voucher_type='RECEIPT'
        BEGIN
          SELECT CASE
            WHEN NOT EXISTS(
              SELECT 1 FROM receipt_headers r
              WHERE CAST(r.receipt_number AS TEXT)=NEW.voucher_id
            )
            THEN RAISE(ABORT, 'CHEQUE_RECEIPT_VOUCHER_NOT_FOUND')
          END;
        END
      ''');
    }

    if (hasVouchers) {
      await db.execute(r'''
        CREATE TRIGGER IF NOT EXISTS trg_cheque_payment_link_exists
        BEFORE INSERT ON cheque_voucher_links
        WHEN NEW.voucher_type='PAYMENT'
        BEGIN
          SELECT CASE
            WHEN NOT EXISTS(
              SELECT 1 FROM vouchers v WHERE v.id=NEW.voucher_id
            )
            THEN RAISE(ABORT, 'CHEQUE_PAYMENT_VOUCHER_NOT_FOUND')
          END;
        END
      ''');
    }
  }

  static Future<void> _ensureChequeAccounts(DatabaseExecutor db) async {
    await _ensureAccount(
      db,
      code: '1020',
      name: 'شيكات واردة',
      type: 'ASSET',
      normalBalance: 'DEBIT',
    );
    await _ensureAccount(
      db,
      code: '1030',
      name: 'شيكات صادرة / أوراق دفع',
      type: 'LIABILITY',
      normalBalance: 'CREDIT',
    );
  }

  static Future<int> _ensureAccount(
    DatabaseExecutor db, {
    required String code,
    required String name,
    required String type,
    required String normalBalance,
  }) async {
    final existing = await db.query(
      'accounts',
      columns: ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final value = existing.first['id'];
      return value is int ? value : int.parse(value.toString());
    }

    return db.insert(
        'accounts',
        {
          'code': code,
          'name': name,
          'type': type,
          'normal_balance': normalBalance,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String col,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (!info.any((row) => row['name'] == col)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $col $type');
    }
  }

  static Future<int> createCheque(
    DatabaseExecutor db,
    Map<String, dynamic> data,
  ) async {
    await ensureChequesSchema(db);
    return db.insert(
      'cheques',
      data,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static Future<void> updateChequeStatus(
    DatabaseExecutor db,
    int chequeId,
    String status,
  ) async {
    await db.update(
      'cheques',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id=?',
      whereArgs: [chequeId],
    );
  }

  static Future<void> linkChequeToPayment(
    DatabaseExecutor db,
    int chequeId,
    String paymentId,
  ) async {
    await db.update(
      'cheques',
      {
        'payment_id': paymentId,
        'source_type': 'PAYMENT',
        'source_id': paymentId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [chequeId],
    );
  }

  static Future<void> addLinkedPayment(
    DatabaseExecutor db,
    int chequeId,
    String paymentId,
  ) async {
    final rows = await db.query(
      'cheques',
      columns: ['linked_payment_ids'],
      where: 'id=?',
      whereArgs: [chequeId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final ids = <String>[];
    final raw = rows.first['linked_payment_ids']?.toString() ?? '';
    if (raw.trim().isNotEmpty) {
      try {
        ids.addAll(List<String>.from(jsonDecode(raw)));
      } catch (_) {}
    }
    if (!ids.contains(paymentId)) ids.add(paymentId);

    await db.update(
      'cheques',
      {
        'linked_payment_ids': jsonEncode(ids),
        'payment_id': paymentId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [chequeId],
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingCheques(
    DatabaseExecutor db,
  ) async {
    await ensureChequesSchema(db);
    return db.query(
      'cheques',
      where: 'status=?',
      whereArgs: ['pending'],
      orderBy: 'due_date ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getChequesByClient(
    DatabaseExecutor db,
    int clientId,
  ) async {
    await ensureChequesSchema(db);
    return db.query(
      'cheques',
      where: 'client_id=?',
      whereArgs: [clientId],
      orderBy: 'issue_date DESC',
    );
  }

  // P0.008: maturity is NOT a returned/bounced event.
  // A due cheque remains pending until a user records an actual lifecycle event.
  static Future<void> checkAutoChequeReturns() async {
    final db = await DBService.database;
    await ensureChequesSchema(db);
  }

  static Future<int> createVoucher(
    DatabaseExecutor db,
    Map<String, dynamic> data,
  ) {
    return db.insert('vouchers', data);
  }
}
