// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/services/purchase_payment_service.dart
// PurchasePaymentService — FINAL v50 COMPATIBLE
// -----------------------------------------------------------------------------
// - يدعم سداد فاتورة بدون supplierPid
// - يمنع خطأ "Invalid supplier id"
// - يحدّث paid_total والمتبقي مباشرة
// - لا ينشئ أي ربط محاسبي مع المورد عند عدم توفره
// - يترك اختيار الحساب داخل شاشة السند
// -----------------------------------------------------------------------------

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:uuid/uuid.dart';

class PurchasePaymentService {
  /// دفع فاتورة مشتريات
  static Future<bool> payPurchase({
    required String purchaseId,
    required double amount,
    required DateTime date,
    String? supplierPid, // optional now
    String? notes,
  }) async {
    final db = await DBService.database;

    // جلب بيانات الفاتورة الحالية
    final rows = await db.rawQuery("""
      SELECT amount, paid_total
      FROM purchases
      WHERE id = ?
      LIMIT 1
    """, [purchaseId]);

    if (rows.isEmpty) return false;

    final amountDue = (rows.first['amount'] as num).toDouble();
    final alreadyPaid = (rows.first['paid_total'] as num).toDouble();
    final newPaid = alreadyPaid + amount;

    // تحديث إجمالي المدفوع
    await db.update(
      'purchases',
      {'paid_total': newPaid},
      where: 'id = ?',
      whereArgs: [purchaseId],
    );

    // إنشاء سجل السداد داخل جدول purchase_payments
    final paymentId = const Uuid().v4();
    await db.insert('purchase_payments', {
      'id': paymentId,
      'purchase_id': purchaseId,
      'supplier_pid': supplierPid, // may be null — allowed
      'amount': amount,
      'date': date.toIso8601String(),
      'notes': notes,
    });

    return true;
  }
}
