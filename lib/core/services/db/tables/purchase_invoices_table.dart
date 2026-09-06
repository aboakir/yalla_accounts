import 'package:sqflite/sqflite.dart';

class PurchaseInvoicesTable {
  // ===========================================================================
  // CREATE ALL TABLES
  // ===========================================================================
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createPurchaseInvoicesTable(db);
    await _createPurchaseInvoiceLinesTable(db);
    await _ensurePurchaseInvoiceIndexes(db);
    await _ensurePurchaseInvoicesSchema(db);
  }

  // ===========================================================================
  // 📌 جدول فواتير الشراء (الرأس)
  // ===========================================================================
  static Future<void> _createPurchaseInvoicesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_invoices (
        id TEXT PRIMARY KEY,
        supplier_id INTEGER NOT NULL,

        invoice_number TEXT,
        purchase_type TEXT,

        subtotal REAL DEFAULT 0,
        vat REAL DEFAULT 0,
        total REAL DEFAULT 0,

        amount_total REAL DEFAULT 0,   -- ★ إصلاح أساسي
        paid_total REAL DEFAULT 0,

        status TEXT DEFAULT 'UNPAID',

        date TEXT NOT NULL,
        note TEXT,

        method TEXT,
        gl_entry_id INTEGER,

        created_at TEXT,
        updated_at TEXT
      );
    ''');
  }

  // ===========================================================================
  // 📌 جدول بنود الفاتورة (نحافظ على الأعمدة القديمة + نضيف الجديدة)
  // ===========================================================================
  static Future<void> _createPurchaseInvoiceLinesTable(
      DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_invoice_lines (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,

        item TEXT,
        item_name TEXT,                  -- ★ للكود الجديد
        qty REAL NOT NULL DEFAULT 1,
        unit_price REAL DEFAULT 0,
        price REAL DEFAULT 0,            -- ★ للكود الجديد
        total REAL DEFAULT 0,
        category TEXT,

        note TEXT,

        FOREIGN KEY(invoice_id) REFERENCES purchase_invoices(id)
          ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_purchase_line_inv
      ON purchase_invoice_lines(invoice_id);
    ''');
  }

  // ===========================================================================
  // Indexes
  // ===========================================================================
  static Future<void> _ensurePurchaseInvoiceIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pinv_supplier ON purchase_invoices(supplier_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pinv_date ON purchase_invoices(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pinv_status ON purchase_invoices(status)');
  }

  // ===========================================================================
  // Schema ensure — تحديث الأعمدة المطلوبة *بدون حذف القديم*
  // ===========================================================================
  static Future<void> _ensurePurchaseInvoicesSchema(DatabaseExecutor db) async {
// الرأس
    await _ensureColumn(db, 'purchase_invoices', 'amount_total', 'REAL');
    await _ensureColumn(db, 'purchase_invoices', 'purchase_type', 'TEXT');
    await _ensureColumn(db, 'purchase_invoices', 'subtotal', 'REAL');
    await _ensureColumn(db, 'purchase_invoices', 'vat', 'REAL');
    await _ensureColumn(db, 'purchase_invoices', 'total', 'REAL');
    await _ensureColumn(db, 'purchase_invoices', 'paid_total', 'REAL');
    await _ensureColumn(
        db, 'purchase_invoices', 'remaining', 'REAL'); // ⭐ السطر المهم
    await _ensureColumn(db, 'purchase_invoices', 'status', 'TEXT');
    await _ensureColumn(db, 'purchase_invoices', 'method', 'TEXT');
    await _ensureColumn(db, 'purchase_invoices', 'gl_entry_id', 'INTEGER');
    await _ensureColumn(db, 'purchase_invoices', 'created_at', 'TEXT');
    await _ensureColumn(db, 'purchase_invoices', 'updated_at', 'TEXT');

    // البنود
    await _ensureColumn(db, 'purchase_invoice_lines', 'item_name', 'TEXT');
    await _ensureColumn(db, 'purchase_invoice_lines', 'price', 'REAL');
    await _ensureColumn(db, 'purchase_invoice_lines', 'category', 'TEXT');
    await _ensureColumn(db, 'purchase_invoice_lines', 'note', 'TEXT');
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================
  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
    }
  }

  // ===========================================================================
  // ✔ API
  // ===========================================================================
  static Future<Map<String, dynamic>?> getById(
      DatabaseExecutor db, String id) async {
    final res = await db.query(
      'purchase_invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  static Future<List<Map<String, dynamic>>> getAll(DatabaseExecutor db) async {
    return await db.query(
      'purchase_invoices',
      orderBy: 'date DESC',
    );
  }

  static Future<int> insert(
      DatabaseExecutor db, Map<String, dynamic> data) async {
    return await db.insert(
      'purchase_invoices',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
