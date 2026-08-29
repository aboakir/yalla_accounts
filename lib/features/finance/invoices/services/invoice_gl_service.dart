// 📁 lib/features/finance/invoices/services/invoice_gl_service.dart
//
// InvoiceGLService — إنشاء فاتورة مبيعات وربطها مع GL.
// القيود:
//   Dr 1200.C<clientId> ذمم العميل (party: CLIENT, party_id=clientId)
//   Cr 4000 إيراد
//   (+) Cr 2105 ضريبة مستحقة إذا vat > 0
//
// يدعم ربط الفاتورة بملف الإصلاح repair_id + تخزين gl_entry_id.
//
// GL source = 'INVOICE'
//
// الملاحظات:
// - يستخدم حساب العميل الفرعي 1200.C<clientId> مع party_type/party_id.
// - method: 'cash' | 'bank' | 'credit'
//   • إذا 'cash' أو 'bank' نضيف إيصال تحصيل فوري اختياري لاحقاً.
//   • الآن نسجّل الفاتورة كـ AR دائماً على حساب العميل الفرعي.
// - الحقول المالية: subtotal + vat + total. كل القيم موجبة.

import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';

class InvoiceGLService {
  static const _table = 'invoices';

  /// إنشاء جدول الفواتير والفهارس
  static Future<void> ensureTable() async {
    final db = await DBService.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        repair_id TEXT,
        client_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        subtotal REAL NOT NULL,
        vat REAL NOT NULL,
        total REAL NOT NULL,
        method TEXT,              -- cash | bank | credit (للمستقبل)
        note TEXT,
        gl_entry_id INTEGER
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_client ON $_table(client_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_repair ON $_table(repair_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_gl ON $_table(gl_entry_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_date ON $_table(date);',
    );
  }

  /// إنشاء فاتورة + قيد GL
  ///
  /// [subtotal] قبل الضريبة. [vatRate] بالنسبة المئوية 0..100.
  static Future<String> insertInvoice({
    required int clientId,
    String? repairId,
    required DateTime date,
    required double subtotal,
    double vatRate = 0.0, // مثال: 16.0
    String? method, // cash | bank | credit (لا يؤثر على GL هنا)
    String? note,
  }) async {
    await ensureTable();
    if (subtotal <= 0) throw ArgumentError('subtotal must be > 0');
    if (vatRate < 0) throw ArgumentError('vatRate must be >= 0');

    final db = await DBService.database;

    final id = const Uuid().v4();
    final iso = date.toIso8601String();
    final m = _normalizeMethod(method);

    final vat = _round2(subtotal * (vatRate / 100.0));
    final total = _round2(subtotal + vat);

    // حسابات
    final clientAr = await DBService.ensureClientAccount(clientId);
    final rev4000 = await _ensureAccount('4000', 'إيراد', 'REVENUE', 'CREDIT');
    final vat2105 = (vat > 0)
        ? await _ensureAccount(
            '2105', 'ضريبة قيمة مضافة مستحقة', 'LIABILITY', 'CREDIT')
        : null;

    // حفظ الفاتورة أولاً
    await db.insert(_table, {
      'id': id,
      'repair_id': repairId,
      'client_id': clientId,
      'date': iso,
      'subtotal': subtotal,
      'vat': vat,
      'total': total,
      'method': m,
      'note': note,
      'gl_entry_id': null,
    });

    // بناء سطور GL
    final lines = <Map<String, Object?>>[
      // Dr AR
      {
        'account_id': clientAr,
        'debit': total,
        'credit': 0.0,
        'party_type': 'CLIENT',
        'party_id': clientId,
        'invoice_id': id,
        'repair_id': repairId,
      },
      // Cr Revenue
      {
        'account_id': rev4000,
        'debit': 0.0,
        'credit': subtotal,
        'party_type': null,
        'party_id': null,
        'invoice_id': id,
        'repair_id': repairId,
      },
    ];

    if (vat2105 != null && vat > 0) {
      lines.add({
        'account_id': vat2105,
        'debit': 0.0,
        'credit': vat,
        'party_type': null,
        'party_id': null,
        'invoice_id': id,
        'repair_id': repairId,
      });
    }

    // نشر GL
    final glEntryId = await DBService.postEntryGL(
      date: date,
      ref: clientId.toString(),
      source: 'INVOICE',
      sourceId: id,
      note: note ?? 'Invoice $id',
      lines: lines,
    );

    // تحديث مرجع القيد
    await db.update(
      _table,
      {
        'gl_entry_id': glEntryId,
        'post_to_gl': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    return id;
  }

  // ---- Helpers ----

  static String _normalizeMethod(String? method) {
    final m = method?.trim().toLowerCase();
    if (m == 'cash' || m == 'bank' || m == 'credit') return m!;
    return 'credit';
  }

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));

  static Future<int> _ensureAccount(
    String code,
    String name,
    String type,
    String nb,
  ) async {
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: name,
      type: type,
      normalBalance: nb,
    );
  }
}
