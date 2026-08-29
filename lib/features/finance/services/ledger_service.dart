// 📁 lib/features/finance/services/ledger_service.dart
//
// LedgerService (Facade) — نقطة وصول موحّدة لدفتر الأستاذ
// - تفويض كامل إلى LedgerDatabaseService.
// - يساعد على تنفيذ عمليات شائعة مثل الحذف حسب المرجع.
// - createEntryFromRepair أصبح "idempotent" ويحذف أي قيود سابقة لنفس الإصلاح قبل إعادة الإنشاء.

import 'package:yalla_accounts/features/finance/models/ledger_entry.dart';
import 'package:yalla_accounts/features/finance/services/ledger_database_service.dart';

class LedgerService {
  static const String _refTypeRepair = 'Repair';

  /// إضافة قيد واحد
  static Future<int> insertEntry(LedgerEntry entry) {
    return LedgerDatabaseService.insertEntry(entry);
  }

  /// تحديث قيد
  static Future<int> updateEntry(LedgerEntry entry) {
    return LedgerDatabaseService.updateEntry(entry);
  }

  /// حذف قيد
  static Future<int> deleteEntry(int id) {
    return LedgerDatabaseService.deleteEntry(id);
  }

  /// جلب جميع القيود
  static Future<List<LedgerEntry>> getAllEntries() {
    return LedgerDatabaseService.getAllEntries();
  }

  /// جلب حسب نوع المرجع (referenceType) مع نمط referenceId (LIKE)
  static Future<List<LedgerEntry>> getEntriesByType(String referenceType) {
    return LedgerDatabaseService.getEntriesByReference(referenceType, '%');
  }

  /// حذف قيود مرتبطة بمرجع معين
  static Future<int> deleteEntriesByReference({
    required String referenceType,
    required String referenceId,
  }) {
    return LedgerDatabaseService.deleteEntriesByReference(
      referenceType,
      referenceId,
    );
  }

  /// إنشاء/استبدال قيود إصلاح واحدة (إيراد + تكلفة) بأمان (Idempotent)
  ///
  /// ملاحظات:
  /// - هنا لا نحسب المدفوع إطلاقاً؛ الإيراد يُعترف به بقيمة الفاتورة/المبلغ المعتمد.
  /// - التكلفة تُمرَّر جاهزة (cost)، أو تُدار خارج هذه الدالة.
  static Future<void> createEntryFromRepair({
    required String repairId,
    required String date, // ISO 8601
    required double amount, // قيمة الاعتراف بالإيراد
    required double cost, // تكلفة الإصلاح (إن وجدت)
    required String customerName,
  }) async {
    // احذف أي قيود سابقة لنفس الإصلاح
    await LedgerDatabaseService.deleteEntriesByReference(
      _refTypeRepair,
      repairId,
    );

    // إيراد: مدين "العملاء" / دائن "الإيرادات"
    final revenueEntry = LedgerEntry(
      date: date,
      description: 'إيراد إصلاح ($customerName)',
      debitAccount: 'العملاء',
      creditAccount: 'الإيرادات',
      amount: amount,
      referenceType: _refTypeRepair,
      referenceId: repairId,
      isApproved: true,
    );
    await LedgerDatabaseService.insertEntry(revenueEntry);

    // تكلفة (اختياري): مدين "تكلفة البضاعة المباعة" / دائن "المخزون"
    if (cost > 0) {
      final expenseEntry = LedgerEntry(
        date: date,
        description: 'تكلفة إصلاح ($customerName)',
        debitAccount: 'تكلفة البضاعة المباعة',
        creditAccount: 'المخزون',
        amount: cost,
        referenceType: _refTypeRepair,
        referenceId: repairId,
        isApproved: true,
      );
      await LedgerDatabaseService.insertEntry(expenseEntry);
    }
  }
}
