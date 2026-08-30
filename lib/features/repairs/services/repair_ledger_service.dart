// 📁 lib/features/repairs/services/repair_ledger_service.dart
//
// RepairLedgerService — ربط محاسبي مُوحّد و"Idempotent"
// - يستخدم DBService (ليس DBHelper).
// - لا يُسجّل المدفوع هنا إطلاقاً؛ هذا دور payments/journal.
// - ينشئ/يستبدل قيود الإيراد + التكلفة لملف الإصلاح الواحد.
// - يمنع التكرار: يحذف أي قيود سابقة لنفس المرجع قبل الإدراج.
// - الحسابات القياسية: "العملاء" مقابل "الإيرادات"، و"تكلفة البضاعة المباعة" مقابل "المخزون".
// - المبلغ المعتمد = finalApprovedAmount، وإن لم يوجد نستخدم totalFileValue.
// - التاريخ = receivedDate بصيغة ISO.
//
// ملاحظات:
// - isLedgerEnabled: إن لم يكن مفعلاً نتوقف.
// - isLedgerSynced: سنضبطه إلى 1 بعد الإنشاء الناجح، لكن التنفيذ "idempotent" دائماً.
// - لا نستخدم transferFromAccount/transferToAccount هنا حتى لا نكسر التوحيد.

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/models/ledger_entry.dart';
import 'package:yalla_accounts/features/finance/services/ledger_database_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/finance/services/work_cost_calculator.dart';

class RepairLedgerService {
  static const String _refType = 'Repair'; // توحيد الكابيتالايزيشن

  /// ينشئ/يحدّث قيود ملف إصلاح (إيراد + تكلفة) بشكلٍ معاد الدخول بأمان.
  static Future<void> createLedgerEntriesForRepair(Repair repair) async {
    // 1) تمكين محاسبي؟
    if (!repair.isLedgerEnabled) return;

    // 2) قيمة الاعتراف بالإيراد
    final double revenueAmount =
        (repair.finalApprovedAmount ?? repair.totalFileValue);
    if (revenueAmount <= 0) return;

    // 3) تكلفة العمل (إن لم تكن مخزنة نحسبها للشهر)
    final double costAmount = (repair.workCost ??
        await WorkCostCalculator.calculateForMonth(repair.receivedDate));

    final String isoDate = repair.receivedDate.toIso8601String();
    final String displayName = repair.beneficiaryName;
    final String descRevenue =
        'إيراد إصلاح: ${repair.vehicleType} ${repair.vehicleModel} — $displayName';
    final String descCost =
        'تكلفة إصلاح: ${repair.vehicleType} ${repair.vehicleModel} — $displayName';

    // 4) احذف أي قيود سابقة لنفس المرجع (Idempotent)
    await LedgerDatabaseService.deleteEntriesByReference(_refType, repair.id);

    // 5) أدخل قيد الإيراد: مدين "العملاء" / دائن "الإيرادات"
    final revenueEntry = LedgerEntry(
      date: isoDate,
      description: descRevenue,
      debitAccount: 'العملاء',
      creditAccount: 'الإيرادات',
      amount: revenueAmount,
      referenceType: _refType,
      referenceId: repair.id,
      isApproved: true,
    );
    await LedgerDatabaseService.insertEntry(revenueEntry);

    // 6) أدخل قيد التكلفة (إن وُجدت): مدين "تكلفة البضاعة المباعة" / دائن "المخزون"
    if (costAmount > 0) {
      final costEntry = LedgerEntry(
        date: isoDate,
        description: descCost,
        debitAccount: 'تكلفة البضاعة المباعة',
        creditAccount: 'المخزون',
        amount: costAmount,
        referenceType: _refType,
        referenceId: repair.id,
        isApproved: true,
      );
      await LedgerDatabaseService.insertEntry(costEntry);
    }

    // 7) علّم الملف كمُزامَن محاسبيًا (يبقى التنفيذ آمناً عند الإعادة)
    final db = await DBService.database;
    await db.update(
      'repairs',
      {'isLedgerSynced': 1},
      where: 'id = ?',
      whereArgs: [repair.id],
    );
  }
}
