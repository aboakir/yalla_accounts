import 'package:sqflite/sqflite.dart';

/// P11 canonical receipt document schema.
///
/// The header is the user-facing receipt document (RC-xxxxxx). Payment rows
/// remain the financial allocation truth consumed by P10. Allocation rows are
/// an audit bridge between the document and those immutable payment lines.
class ReceiptTables {
  ReceiptTables._();

  static Future<void> createAllTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipt_requests(
        operation_id TEXT PRIMARY KEY, request_json TEXT NOT NULL,
        receipt_number INTEGER NOT NULL UNIQUE)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipt_headers (
        receipt_number INTEGER PRIMARY KEY,
        client_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        method TEXT NOT NULL,
        total_amount REAL NOT NULL,
        allocated_amount REAL NOT NULL DEFAULT 0,
        credit_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'posted',
        reversal_of_receipt_number INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipt_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_number INTEGER NOT NULL,
        payment_id TEXT NOT NULL UNIQUE,
        repair_id TEXT,
        amount REAL NOT NULL,
        allocation_type TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipt_instruments (
        id TEXT PRIMARY KEY,
        receipt_number INTEGER NOT NULL,
        instrument_key TEXT NOT NULL,
        method TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'ILS',
        cheque_id INTEGER,
        bank_account_id INTEGER,
        created_at TEXT NOT NULL,
        CHECK(amount > 0),
        UNIQUE(receipt_number, instrument_key)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_credit_allocations (
        id TEXT PRIMARY KEY,
        client_id INTEGER NOT NULL,
        repair_id TEXT NOT NULL,
        payment_id TEXT NOT NULL UNIQUE,
        amount REAL NOT NULL,
        gl_entry_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Financial document history is append-only; reversal changes only status.
    for (final table in [
      'receipt_headers',
      'receipt_allocations',
      'receipt_instruments',
      'customer_credit_allocations',
      'receipt_requests'
    ]) {
      await db.execute('''CREATE TRIGGER IF NOT EXISTS ${table}_no_delete
        BEFORE DELETE ON $table BEGIN
        SELECT RAISE(ABORT, 'Financial receipt history cannot be deleted'); END''');
      if (table != 'receipt_headers') {
        await db.execute('''CREATE TRIGGER IF NOT EXISTS ${table}_no_update
          BEFORE UPDATE ON $table BEGIN
          SELECT RAISE(ABORT, 'Financial receipt history is immutable'); END''');
      }
    }
    await db
        .execute('''CREATE TRIGGER IF NOT EXISTS receipt_header_values_immutable
      BEFORE UPDATE OF client_id,date,method,total_amount,allocated_amount,
        credit_amount,reversal_of_receipt_number,created_at ON receipt_headers
      BEGIN SELECT RAISE(ABORT, 'Receipt values are immutable; reverse the receipt'); END''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_headers_client ON receipt_headers(client_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_headers_date ON receipt_headers(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_instruments_receipt '
      'ON receipt_instruments(receipt_number)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_instruments_cheque '
      'ON receipt_instruments(cheque_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_allocations_receipt ON receipt_allocations(receipt_number)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_allocations_repair ON receipt_allocations(repair_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_credit_allocations_client ON customer_credit_allocations(client_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_credit_allocations_repair ON customer_credit_allocations(repair_id)',
    );
  }
}
