import 'package:sqflite/sqflite.dart';

class PurchasePaymentsTable {
  // ===========================================================================
  // 🧱 CREATE ALL TABLES
  // ===========================================================================
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createTable(db);
    await _ensureSchema(db);
  }

  // ===========================================================================
  // 🧱 CREATE TABLE purchase_payments
  // ===========================================================================
  static Future<void> _createTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_payments (
        id TEXT PRIMARY KEY,

        invoice_id TEXT NOT NULL,   -- يرتبط بفاتورة الشراء
        amount REAL NOT NULL,
        date TEXT NOT NULL,

        method TEXT,                -- cash / bank / cheque / transfer
        note TEXT,

        gl_entry_id INTEGER,
        created_at TEXT,
        updated_at TEXT,

        FOREIGN KEY(invoice_id) REFERENCES purchase_invoices(id)
          ON DELETE CASCADE
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ppay_invoice ON purchase_payments(invoice_id);',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ppay_date ON purchase_payments(date);',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ppay_method ON purchase_payments(method);',
    );
  }

  // ===========================================================================
  // 🧱 ENSURE SCHEMA — بدون supplier_pid نهائيًا
  // ===========================================================================
  static Future<void> _ensureSchema(DatabaseExecutor db) async {
    await _ensureColumn(db, 'purchase_payments', 'gl_entry_id', 'INTEGER');
    await _ensureColumn(db, 'purchase_payments', 'created_at', 'TEXT');
    await _ensureColumn(db, 'purchase_payments', 'updated_at', 'TEXT');

    // إزالة supplier_pid إن وجد
    await _dropColumnIfExists(db, 'purchase_payments', 'supplier_pid');
  }

  // ===========================================================================
  // ADD COLUMN IF NOT EXISTS
  // ===========================================================================
  static Future<void> _ensureColumn(
      DatabaseExecutor db, String table, String column, String type) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
    }
  }

  // ===========================================================================
  // DROP COLUMN SAFELY
  // ===========================================================================
  static Future<void> _dropColumnIfExists(
      DatabaseExecutor db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((c) => c['name'] == column);
    if (!exists) return;

    final cols =
        info.where((c) => c['name'] != column).map((c) => c['name']).toList();

    final colsList = cols.join(', ');
    final placeholders = cols.join(', ');

    await db.execute('ALTER TABLE $table RENAME TO ${table}_old;');

    await db.execute('''
      CREATE TABLE $table (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        method TEXT,
        note TEXT,
        gl_entry_id INTEGER,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY(invoice_id) REFERENCES purchase_invoices(id)
      );
    ''');

    await db.execute('''
      INSERT INTO $table($colsList)
      SELECT $placeholders FROM ${table}_old;
    ''');

    await db.execute('DROP TABLE ${table}_old;');
  }

  // ===========================================================================
  // READ ALL PAYMENTS FOR INVOICE
  // ===========================================================================
  static Future<List<Map<String, dynamic>>> getByInvoice(
      DatabaseExecutor db, String invoiceId) async {
    return await db.query(
      'purchase_payments',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'date DESC',
    );
  }

  // ===========================================================================
  // INSERT PAYMENT
  // ===========================================================================
  static Future<int> insert(
      DatabaseExecutor db, Map<String, dynamic> data) async {
    return await db.insert(
      'purchase_payments',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
