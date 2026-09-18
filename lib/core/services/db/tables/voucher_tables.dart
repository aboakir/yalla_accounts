// -----------------------------------------------------------------------------
// 📁 lib/core/services/db/tables/voucher_tables.dart
// FINAL — لا client_type — لا مشاكل — يبني جدول vouchers نظيف فوق أي نسخة قديمة
// يدعم الترقية بدون حذف قاعدة البيانات
// -----------------------------------------------------------------------------
import 'package:sqflite/sqflite.dart';

class VoucherTables {
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _rebuildIfLegacy(db);
    await _ensureIndexes(db);
  }

  // ---------------------------------------------------------------------------
  // 1) إعادة بناء الجدول بالكامل إذا كان يحتوي client_type
  // ---------------------------------------------------------------------------
  static Future<void> _rebuildIfLegacy(DatabaseExecutor db) async {
    final info = await db.rawQuery("PRAGMA table_info(vouchers)");
    final cols = info.map((e) => e['name'] as String).toList();

    // إذا ما في جدول أصلاً → يبني واحد جديد جاهز
    if (!cols.contains("id")) {
      await _createFresh(db);
      await _ensurePostedGuards(db);
      return;
    }

    // لو فيه client_type (سبب المشكلة)
    if (cols.contains("client_type")) {
      // Add the canonical columns first so the rebuild can preserve them.
      await _ensureSchema(db);
      await _rebuild(db);
      await _ensureSchema(db);
    } else {
      // فقط يكمل فحص الأعمدة الناقصة
      await _ensureSchema(db);
    }
    await _ensurePostedGuards(db);
  }

  // ---------------------------------------------------------------------------
  // 2) بناء جدول جديد من الصفر
  // ---------------------------------------------------------------------------
  static Future<void> _createFresh(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vouchers (
        id TEXT PRIMARY KEY,
        voucher_type TEXT,
        voucher_number TEXT,
        voucher_code TEXT,
        party_type TEXT,
        party_id TEXT,
        amount REAL,
        currency TEXT DEFAULT 'ILS',
        date TEXT,
        method TEXT,
        cheque_id TEXT,
        reference TEXT,
        source TEXT,
        source_id TEXT,
        gl_entry_id INTEGER,
        is_posted INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'DRAFT',
        reversal_gl_entry_id INTEGER,
        reversed_at TEXT,
        reversal_reason TEXT,
        posted_by TEXT,
        posted_at TEXT,
        notes TEXT,
        attachments TEXT,
        created_at TEXT,
        updated_at TEXT
      );
    ''');
  }

  // ---------------------------------------------------------------------------
  // 3) إعادة بناء الجدول بدون client_type وبدون فقدان بيانات
  // ---------------------------------------------------------------------------
  static Future<void> _rebuild(DatabaseExecutor db) async {
    // 1) إنشاء جدول مؤقت جديد
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vouchers_new (
        id TEXT PRIMARY KEY,
        voucher_type TEXT,
        voucher_number TEXT,
        voucher_code TEXT,
        party_type TEXT,
        party_id TEXT,
        amount REAL,
        currency TEXT DEFAULT 'ILS',
        date TEXT,
        method TEXT,
        cheque_id TEXT,
        reference TEXT,
        source TEXT,
        source_id TEXT,
        gl_entry_id INTEGER,
        is_posted INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'DRAFT',
        reversal_gl_entry_id INTEGER,
        reversed_at TEXT,
        reversal_reason TEXT,
        posted_by TEXT,
        posted_at TEXT,
        notes TEXT,
        attachments TEXT,
        created_at TEXT,
        updated_at TEXT
      );
    ''');

    // 2) نقل البيانات مع تجاهل client_type
    await db.execute('''
      INSERT INTO vouchers_new
      SELECT
        id,
        voucher_type,
        voucher_number,
        voucher_code,
        party_type,
        party_id,
        amount,
        currency,
        date,
        method,
        cheque_id,
        reference,
        source,
        source_id,
        gl_entry_id,
        is_posted,
        status,
        reversal_gl_entry_id,
        reversed_at,
        reversal_reason,
        posted_by,
        posted_at,
        notes,
        attachments,
        created_at,
        updated_at
      FROM vouchers;
    ''');

    // 3) حذف الجدول القديم
    await db.execute("DROP TABLE vouchers;");

    // 4) إعادة تسمية الجدول الجديد
    await db.execute("ALTER TABLE vouchers_new RENAME TO vouchers;");
  }

  // ---------------------------------------------------------------------------
  // 4) ضمان الأعمدة الناقصة (بعد إعادة البناء)
  // ---------------------------------------------------------------------------
  static Future<void> _ensureSchema(DatabaseExecutor db) async {
    await _ensure(db, 'voucher_type', 'TEXT');
    await _ensure(db, 'voucher_number', 'TEXT');
    await _ensure(db, 'voucher_code', 'TEXT');
    await _ensure(db, 'party_type', 'TEXT');
    await _ensure(db, 'party_id', 'TEXT');
    await _ensure(db, 'amount', 'REAL');
    await _ensure(db, 'currency', "TEXT DEFAULT 'ILS'");
    await _ensure(db, 'date', 'TEXT');
    await _ensure(db, 'method', 'TEXT');
    await _ensure(db, 'cheque_id', 'TEXT');
    await _ensure(db, 'reference', 'TEXT');
    await _ensure(db, 'source', 'TEXT');
    await _ensure(db, 'source_id', 'TEXT');
    await _ensure(db, 'gl_entry_id', 'INTEGER');
    await _ensure(db, 'is_posted', 'INTEGER NOT NULL DEFAULT 0');
    await _ensure(db, 'status', "TEXT NOT NULL DEFAULT 'DRAFT'");
    await _ensure(db, 'reversal_gl_entry_id', 'INTEGER');
    await _ensure(db, 'reversed_at', 'TEXT');
    await _ensure(db, 'reversal_reason', 'TEXT');
    await _ensure(db, 'posted_by', 'TEXT');
    await _ensure(db, 'posted_at', 'TEXT');
    await _ensure(db, 'notes', 'TEXT');
    await _ensure(db, 'attachments', 'TEXT');
    await _ensure(db, 'created_at', 'TEXT');
    await _ensure(db, 'updated_at', 'TEXT');
  }

  // ---------------------------------------------------------------------------
  // 5) إضافة عمود إن كان ناقص
  // ---------------------------------------------------------------------------
  static Future<void> _ensure(
      DatabaseExecutor db, String column, String type) async {
    final info = await db.rawQuery("PRAGMA table_info(vouchers)");
    final exists = info.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute("ALTER TABLE vouchers ADD COLUMN $column $type;");
    }
  }

  /// Runs a narrowly-scoped schema backfill that may need to populate
  /// compatibility metadata on already-posted vouchers.
  ///
  /// Runtime/business writes never use this path. The immutable-posted-voucher
  /// guard is removed only for the duration of the trusted migration action and
  /// is restored in finally even if the migration throws.
  static Future<T> runTrustedPostedVoucherBackfill<T>(
    DatabaseExecutor db,
    Future<T> Function() action,
  ) async {
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_vouchers_posted_material_update;',
    );
    try {
      return await action();
    } finally {
      await _ensurePostedGuards(db);
    }
  }

  static Future<void> _ensurePostedGuards(DatabaseExecutor db) async {
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_vouchers_posted_material_update;',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_vouchers_posted_delete;',
    );

    await db.execute(r'''
      CREATE TRIGGER trg_vouchers_posted_material_update
      BEFORE UPDATE OF
        voucher_type, party_type, party_id, amount, currency, date,
        method, cheque_id, reference, source, source_id
      ON vouchers
      WHEN OLD.is_posted = 1 OR OLD.gl_entry_id IS NOT NULL
      BEGIN
        SELECT RAISE(
          ABORT,
          'Posted voucher is immutable; use formal reversal/correcting voucher'
        );
      END;
    ''');

    await db.execute(r'''
      CREATE TRIGGER trg_vouchers_posted_delete
      BEFORE DELETE ON vouchers
      WHEN OLD.is_posted = 1 OR OLD.gl_entry_id IS NOT NULL
      BEGIN
        SELECT RAISE(
          ABORT,
          'Posted voucher cannot be deleted; use formal reversal'
        );
      END;
    ''');
  }

  // ---------------------------------------------------------------------------
  // 6) إنشاء فهارس
  // ---------------------------------------------------------------------------
  static Future<void> _ensureIndexes(DatabaseExecutor db) async {
    await db
        .execute("CREATE INDEX IF NOT EXISTS idx_v_date ON vouchers(date);");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_v_party ON vouchers(party_id);");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_v_type ON vouchers(voucher_type);");
  }
}
