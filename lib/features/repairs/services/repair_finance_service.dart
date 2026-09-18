// ---------------------------------------------------------------------------
// 📁 lib/features/repairs/services/repair_finance_service.dart
//
// FINAL VERSION — FULLY COMPATIBLE WITH PAYMENT MODEL v2025
// ---------------------------------------------------------------------------
// • حذف partyId لأنه لم يعد موجوداً في الموديل
// • status أصبح String وليس Enum
// • إضافة isIncome (required)
// • متوافق تماماً مع PaymentService / InvoiceService
// • حساب subtotal + VAT + إنشاء فاتورة + ترحيل GL
// ---------------------------------------------------------------------------

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';

import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';

class RepairFinanceService {
  // =====================================================================
  //  تسجيل دفعة على ملف إصلاح — Receipt Payment
  // =====================================================================

  static Future<void> addPaymentFromRepair({
    required Repair repair,
    required double amount,
    required String method,
    String? notes,
    DateTime? date,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('قيمة الدفعة يجب أن تكون أكبر من صفر');
    }

    final normalized = _normalizeMethod(method);
    final when = date ?? DateTime.now();

    final p = Payment(
      id: "", // ← سيتم توليده لاحقاً
      clientId: repair.clientId,
      repairId: repair.id,
      relatedRepairId: repair.id,
      invoiceId: repair.invoiceId,
      amount: double.parse(amount.toStringAsFixed(2)),
      date: when,
      method: normalized,
      accountName: normalized,
      status: "confirmed", // ← String وليس Enum
      notes: (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      attachments: null,
      glEntryId: null,

      // REQUIRED FIELD في الـ Payment model الجديد
      isIncome: true, // ← دفعة قبض للعميل
    );

    await PaymentService.insertAndPostReceipt(
      payment: p,
      customerName: repair.beneficiaryName,
      method: normalized,
      descriptionOverride: notes,
      updateInvoice: true,
    );
  }

  // =====================================================================
  //  نسخة تستخدم repairId مباشرة
  // =====================================================================

  static Future<void> addPaymentFromRepairId({
    required String repairId,
    required double amount,
    required String method,
    String? notes,
    DateTime? date,
  }) async {
    final svc = await RepairsService.instance();
    final r = await svc.getById(repairId);

    if (r == null) {
      throw ArgumentError('لم يتم العثور على ملف الإصلاح');
    }

    await addPaymentFromRepair(
      repair: r,
      amount: amount,
      method: method,
      notes: notes,
      date: date,
    );
  }

  // =====================================================================
  //  اعتماد السعر النهائي + إنشاء الفاتورة + GL
  // =====================================================================

  static Future<String> approveFinalAmount(
    Repair repair, {
    double vatRate = 0.0,
    String? method,
    String? note,
    String approvedBy = 'SYSTEM',
  }) async {
    // subtotal
    final subtotal = _computeSubtotal(repair);

    // VAT
    final vat = _round2(subtotal * (vatRate.clamp(0, 100) / 100));
    final total = _round2(subtotal + vat);

    // إنشاء الفاتورة + ترحيل GL
    final invoiceId = await InvoiceService.I.createInvoice(
      id: repair.invoiceId,
      repairId: repair.id,
      date: DateTime.now(),
      subtotal: subtotal,
      vatAmount: vat,
      total: total,
      clientId: repair.clientId,
      notes: note,
      status: 'unpaid',
      method: method,
      postToGL: true,
    );

    // إعادة احتساب المدفوع والمتبقي (Totals)
    await InvoiceService.I.recomputeForRepair(repair.id);

    // تحديث ملف الإصلاح
    final updated = repair.copyWith(
      finalApprovedAmount: total,
      invoiceId: invoiceId,
      isLedgerEnabled: true,
      isLedgerSynced: true,
      approvedAt: DateTime.now(),
      approvedBy: approvedBy,
      status: 'APPROVED',
      updatedAt: DateTime.now(),
    );

    final svc = await RepairsService.instance();
    await svc.updateRepair(updated);

    return invoiceId;
  }

  // =====================================================================
  // Helpers
  // =====================================================================

  static double _computeSubtotal(Repair r) {
    double sum = 0.0;

    Iterable asList(dynamic a) => (a is List) ? a : const [];

    double priceOf(Map m) {
      final p = m['price'] ?? m['amount'] ?? m['cost'] ?? 0;
      final q = m['qty'] ?? m['quantity'] ?? 1;

      final price = (p is num) ? p.toDouble() : double.tryParse('$p') ?? 0.0;
      final qty = (q is num) ? q.toDouble() : double.tryParse('$q') ?? 1.0;

      return price * qty;
    }

    for (final x in asList(r.works)) {
      if (x is Map) sum += priceOf(x);
    }
    for (final x in asList(r.parts)) {
      if (x is Map) sum += priceOf(x);
    }

    // fallback — في حال ما في أعمال/قطع
    if (sum <= 0) {
      sum = r.fileValue.toDouble();
    }

    return _round2(sum);
  }

  static String _normalizeMethod(String raw) {
    final m = raw.trim().toLowerCase();

    const cash = {'cash', 'كاش', 'صندوق', 'نقد', 'نقدًا', 'نقدا'};
    const bank = {
      'bank',
      'بنك',
      'تحويل',
      'تحويل بنكي',
      'pos',
      'card',
      'visa',
      'master',
      'شيك',
      'check',
      'cheque',
    };

    if (cash.any((e) => m.contains(e))) return 'cash';
    if (bank.any((e) => m.contains(e))) return 'bank';

    return 'cash';
  }

  static double _round2(double x) => double.parse(x.toStringAsFixed(2));
}
