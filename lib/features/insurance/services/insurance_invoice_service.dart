// 📁 lib/features/insurance/services/insurance_invoice_service.dart
//
// InsuranceInvoiceService — موحّد مع DBService
// - لا ينشئ جدول بنفسه.
// - ensureTable(): يتأكد من وجود الجدول ويُنشئ الفهارس فقط.
// - CRUD باستخدام DBService.database.
// - لو الجدول غير موجود: يرمي StateError مع رسالة توضّح إضافة الجدول في DBService.
//
// ملاحظة مهمة:
// 1) تأكد أن لديك الموديل: features/insurance/models/insurance_invoice.dart
//    وفيه toMap()/fromMap() متوافقين مع الأعمدة أدناه.
// 2) لازم تضيف إنشاء الجدول داخل DBService (انظر التعليق داخل ensureTable).

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/insurance/models/insurance_invoice.dart';

class InsuranceInvoiceService {
  InsuranceInvoiceService._();
  static const String tableName = 'insurance_invoices';

  // ======== DB handle ========
  static Future<Database> _db() async => DBService.database;

  // ======== Schema guard ========
  static Future<void> ensureTable() async {
    final db = await _db();

    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [tableName],
    );

    if (rows.isEmpty) {
      // 👇 وضّح للمطور أين يضيف إنشاء الجدول (داخل DBService فقط)
      throw StateError(
        'جدول $tableName غير موجود. '
        'أنشئه داخل DBService فقط (مصدر الحقيقة). '
        'أضف دالة إنشاء داخل DBService مثل:\n\n'
        '  static Future<void> _createInsuranceInvoicesTable(DatabaseExecutor db) async {\n'
        "    await db.execute('''\n"
        '      CREATE TABLE IF NOT EXISTS $tableName (\n'
        '        id TEXT PRIMARY KEY,\n'
        '        invoice_number TEXT NOT NULL,\n'
        '        client_name TEXT NOT NULL,\n'
        '        insurance_company TEXT NOT NULL,\n'
        '        amount REAL NOT NULL,\n'
        '        date TEXT NOT NULL,\n'
        '        status TEXT NOT NULL\n'
        '      )\n'
        "    ''');\n"
        '    await db.execute(\'CREATE INDEX IF NOT EXISTS idx_${tableName}_date ON $tableName(date);\');\n'
        '    await db.execute(\'CREATE INDEX IF NOT EXISTS idx_${tableName}_status ON $tableName(status);\');\n'
        '  }\n\n'
        'ولا تنسَ استدعاء الدالة داخل onCreate/onUpgrade في DBService.',
      );
    }

    // فهارس (آمنة إن وُجدت)
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_date ON $tableName(date);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_status ON $tableName(status);');
  }

  // ======== CRUD ========

  static Future<int> insertInvoice(InsuranceInvoice invoice) async {
    await ensureTable();
    final db = await _db();
    return await db.insert(
      tableName,
      invoice.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static Future<List<InsuranceInvoice>> getAllInvoices() async {
    await ensureTable();
    final db = await _db();
    final result = await db.query(tableName, orderBy: 'date DESC');
    return result.map(InsuranceInvoice.fromMap).toList();
  }

  static Future<InsuranceInvoice?> getById(String id) async {
    await ensureTable();
    final db = await _db();
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InsuranceInvoice.fromMap(rows.first);
  }

  static Future<int> updateInvoice(InsuranceInvoice invoice) async {
    await ensureTable();
    final db = await _db();
    return await db.update(
      tableName,
      invoice.toMap(),
      where: 'id = ?',
      whereArgs: [invoice.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static Future<int> deleteInvoice(String id) async {
    await ensureTable();
    final db = await _db();
    return await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  // ======== استعلامات مساعدة ========

  /// البحث بالنص على رقم/عميل/شركة تأمين، اختياريًا مع حالة (paid|partial|unpaid...).
  static Future<List<InsuranceInvoice>> search({
    String? query,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    await ensureTable();
    final db = await _db();

    final where = <String>[];
    final args = <Object?>[];

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      where.add(
          '(invoice_number LIKE ? OR client_name LIKE ? OR insurance_company LIKE ?)');
      args.addAll([q, q, q]);
    }

    if (status != null && status.trim().isNotEmpty) {
      where.add('status = ?');
      args.add(status.trim());
    }

    final rows = await db.query(
      tableName,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map(InsuranceInvoice.fromMap).toList();
  }
}
