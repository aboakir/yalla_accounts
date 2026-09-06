// ---------------------------------------------------------------------------
// 📁 lib/core/services/db/tables/payments_tables.dart
// جدول المدفوعات — الآن يدعم رقم سند قصير receipt_number
// ---------------------------------------------------------------------------

import 'package:sqflite/sqflite.dart';

class PaymentsTables {
  // ============================================================
  // 🧱 CREATE ALL TABLES
  // ============================================================
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createPaymentsTable(db);
    await _ensurePaymentsIndexes(db);
    await ensurePaymentsSchema(db);
  }

  // ============================================================
  // 📌 CREATE TABLE payments
  // ============================================================
  static Future<void> _createPaymentsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payments(
        id TEXT PRIMARY KEY,              -- UUID الداخلي

        receipt_number INTEGER,           -- ⭐ رقم سند قصير يظهر للمستخدم
        reversal_of_payment_id TEXT,       -- P11 formal counter-receipt link

        party_id TEXT,
        client_id INTEGER,
        repair_id TEXT,
        invoice_id TEXT,

        amount REAL NOT NULL,
        date TEXT NOT NULL,
        method TEXT NOT NULL,

        accountName TEXT,
        status TEXT,
        notes TEXT,
        attachments TEXT,

        relatedRepairId TEXT,

        gl_entry_id INTEGER,
        cheque_id INTEGER,

        isIncome INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  // ============================================================
  // 📌 INDEXES
  // ============================================================
  static Future<void> _ensurePaymentsIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_party ON payments(party_id);');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_client ON payments(client_id);');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_repair ON payments(repair_id);');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_invoice ON payments(invoice_id);');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(date);');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_gl ON payments(gl_entry_id);');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_cheque ON payments(cheque_id);');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_receipt_num ON payments(receipt_number);');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_reversal_of ON payments(reversal_of_payment_id);');
  }

  // ============================================================
  // 📌 SCHEMA ENSURE (SAFE ALTER)
  // ============================================================
  static Future<void> ensurePaymentsSchema(DatabaseExecutor db) async {
    // 1) إضافة العمود الجديد إذا مفقود
    await ensureColumnOn(
      db: db,
      table: 'payments',
      column: 'receipt_number',
      type: 'INTEGER',
    );

    await ensureColumnOn(
      db: db,
      table: 'payments',
      column: 'reversal_of_payment_id',
      type: 'TEXT',
    );

    // 2) باقي الأعمدة
    await ensureColumnOn(
      db: db,
      table: 'payments',
      column: 'party_id',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'payments',
      column: 'cheque_id',
      type: 'INTEGER',
    );

    await ensureColumnOn(
      db: db,
      table: 'payments',
      column: 'gl_entry_id',
      type: 'INTEGER',
    );

    await ensureColumnOn(
      db: db,
      table: 'payments',
      column: 'relatedRepairId',
      type: 'TEXT',
    );

    await ensureColumnOn(
      db: db,
      table: 'payments',
      column: 'isIncome',
      type: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _ensurePaymentsIndexes(db);
  }

  // ============================================================
  // 🔧 ADD COLUMN SAFELY
  // ============================================================
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

  // ============================================================
  // 🔧 DROP COLUMN (غير مستخدم)
  // ============================================================
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
        receipt_number INTEGER,
        reversal_of_payment_id TEXT,
        party_id TEXT,
        client_id INTEGER,
        repair_id TEXT,
        invoice_id TEXT,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        method TEXT NOT NULL,
        accountName TEXT,
        status TEXT,
        notes TEXT,
        attachments TEXT,
        relatedRepairId TEXT,
        gl_entry_id INTEGER,
        cheque_id INTEGER,
        isIncome INTEGER NOT NULL DEFAULT 1
      );
    ''');

    await db.execute('''
      INSERT INTO $table($colsList)
      SELECT $placeholders FROM ${table}_old;
    ''');

    await db.execute('DROP TABLE ${table}_old;');
  }
}
