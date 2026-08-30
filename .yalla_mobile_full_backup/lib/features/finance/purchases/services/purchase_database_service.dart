// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/services/purchase_database_service.dart
//
// PurchaseDatabaseService — FINAL v51 COMPLIANT
// -----------------------------------------------------------------------------
// • يعتمد على الجداول الجديدة:
//      purchase_invoices
//      purchase_invoice_lines
// • بدون supplierPid نهائياً
// • بدون supplierName — نستعمل supplier_id فقط
// • insertInvoice(): إدخال رأس فاتورة فقط بدون GL
// • listLast(), getById(): قراءة بيانات الفواتير
//
// ملاحظة مهمة:
// هذا الملف لا ينشر GL إطلاقاً. النشر يتم داخل PurchaseInvoiceService.
// -----------------------------------------------------------------------------

import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';

class PurchaseDatabaseService {
  static const String _tableHeader = 'purchase_invoices';
  static const String _tableLines = 'purchase_invoice_lines';
  static const _uuid = Uuid();

  static Future<Database> get _db async => DBService.database;

  // -----------------------------------------------------------------------------
  // 🧱 ensureTables() — يضمن وجود الجداول الأساسية
  // -----------------------------------------------------------------------------
  static Future<void> ensureTables([DatabaseExecutor? exec]) async {
    final db = exec ?? await _db;

    // جدول الفاتورة (الرأس)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableHeader (
        id TEXT PRIMARY KEY,
        supplier_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        amount_total REAL NOT NULL,
        paid_total REAL DEFAULT 0,
        status TEXT,
        purchase_type TEXT,
        gl_entry_id INTEGER
      );
    ''');

    // جدول البنود
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableLines (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        qty REAL NOT NULL,
        price REAL NOT NULL,
        total REAL NOT NULL
      );
    ''');

    // فهارس
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_date ON $_tableHeader(date);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_supplier ON $_tableHeader(supplier_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_gl ON $_tableHeader(gl_entry_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_lines_invoice ON $_tableLines(invoice_id);');
  }

  // -----------------------------------------------------------------------------
  // INSERT HEADER ONLY — quick (no GL)
  // -----------------------------------------------------------------------------
  static Future<String> insertInvoice({
    required int supplierId,
    required DateTime date,
    required double amountTotal,
    String? note,
    String? status,
    String purchaseType = "OTHER",
    String? id,
  }) async {
    final db = await _db;

    return await db.transaction<String>((txn) async {
      await ensureTables(txn);

      final invoiceId =
          (id != null && id.trim().isNotEmpty) ? id.trim() : _uuid.v4();

      await txn.insert(
        _tableHeader,
        {
          'id': invoiceId,
          'supplier_id': supplierId,
          'date': date.toIso8601String(),
          'note': note,
          'amount_total': amountTotal,
          'paid_total': 0.0,
          'status': status,
          'purchase_type': purchaseType,
          'gl_entry_id': null,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return invoiceId;
    });
  }

  // -----------------------------------------------------------------------------
  // قراءة آخر الفواتير
  // -----------------------------------------------------------------------------
  static Future<List<Map<String, Object?>>> listLast({int limit = 50}) async {
    final db = await _db;
    await ensureTables(db);

    return db.query(
      _tableHeader,
      orderBy: 'date DESC',
      limit: limit,
    );
  }

  // -----------------------------------------------------------------------------
  // قراءة فاتورة واحدة حسب ID
  // -----------------------------------------------------------------------------
  static Future<Map<String, Object?>?> getById(String id) async {
    final db = await _db;
    await ensureTables(db);

    final r = await db.query(
      _tableHeader,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return r.isEmpty ? null : r.first;
  }
}
