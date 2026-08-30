// 📁 lib/features/repairs/services/repair_invoice_service.dart
//
// RepairInvoiceService — إنشاء فاتورة من إصلاح وربطها بالـ GL.
// يعتمد InvoiceGLService تحت الغطاء.
//
// السيناريو:
//   • عند إنهاء الإصلاح = ننشئ فاتورة:
//       Dr 1200 ذمم العملاء (CLIENT party)
//       Cr 4000 إيراد (+ Cr 2105 إن وُجد VAT)
//   • نخزّن invoice_id داخل repairs.
//
// لاحقاً يمكننا توليد subtotal من بنود الإصلاح. الآن نستقبله كقيمة.

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';

class RepairInvoiceService {
  static const _repairs = 'repairs';

  /// تأكيد وجود عمود ربط الفاتورة داخل جدول الإصلاحات
  static Future<void> ensureRepairsTable() async {
    final db = await DBService.database;

    // جدول بسيط إذا مش موجود
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_repairs (
        id TEXT PRIMARY KEY,
        client_id INTEGER,
        date TEXT,
        status TEXT,
        total_estimate REAL,
        invoice_id TEXT          -- ربط الفاتورة
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repairs_invoice ON $_repairs(invoice_id);',
    );
  }

  /// ينشئ فاتورة لملف إصلاح ويحدث repair.invoice_id
  ///
  /// ملاحظات:
  /// - يحتاج clientId و subtotal صريحين حالياً.
  /// - vatRate نسبة مئوية مثل 0 أو 16.
  /// - method لا يؤثر على GL هنا. الدفع يتم لاحقاً عبر PaymentService.
  static Future<String> createInvoiceForRepair({
    required String repairId,
    required int clientId,
    required DateTime date,
    required double subtotal,
    double vatRate = 0.0,
    String? method, // 'cash' | 'bank' | 'credit' (للمستقبل)
    String? note,
  }) async {
    await ensureRepairsTable();
    if (subtotal <= 0) {
      throw ArgumentError('subtotal must be > 0');
    }
    if (vatRate < 0) {
      throw ArgumentError('vatRate must be >= 0');
    }

    final db = await DBService.database;

    // تحقق بسيط أن الإصلاح موجود
    final repair = await db.query(
      _repairs,
      columns: ['id', 'invoice_id', 'client_id'],
      where: 'id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (repair.isEmpty) {
      throw StateError('repair not found: $repairId');
    }
    // منع التكرار
    final existingInv = repair.first['invoice_id'] as String?;
    if (existingInv != null && existingInv.isNotEmpty) {
      return existingInv; // already invoiced
    }

    final vatAmount =
        double.parse((subtotal * (vatRate / 100.0)).toStringAsFixed(2));
    final total = double.parse((subtotal + vatAmount).toStringAsFixed(2));

    // P0.006 — all Repair -> Invoice creation goes through the same
    // immutable, atomic InvoiceService lifecycle.
    return InvoiceService.I.createInvoice(
      repairId: repairId,
      date: date,
      subtotal: subtotal,
      vatAmount: vatAmount,
      total: total,
      clientId: clientId,
      method: method,
      note: note ?? 'Invoice for repair $repairId',
      postToGL: true,
    );
  }
}
