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
      return;
    }

    // لو فيه client_type (سبب المشكلة)
    if (cols.contains("client_type")) {
      await _rebuild(db);
    } else {
      // فقط يكمل فحص الأعمدة الناقصة
      await _ensureSchema(db);
    }
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
        gl_entry_id INTEGER,
        is_posted INTEGER NOT NULL DEFAULT 0,
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
        gl_entry_id INTEGER,
        is_posted INTEGER NOT NULL DEFAULT 0,
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
        gl_entry_id,
        is_posted,
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
    await _ensure(db, 'gl_entry_id', 'INTEGER');
    await _ensure(db, 'is_posted', 'INTEGER NOT NULL DEFAULT 0');
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
