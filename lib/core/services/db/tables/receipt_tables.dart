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

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_headers_client ON receipt_headers(client_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_headers_date ON receipt_headers(date)',
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
