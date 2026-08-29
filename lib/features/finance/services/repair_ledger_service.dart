import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/finance/models/ledger_entry.dart';
import 'package:yalla_accounts/features/finance/services/ledger_database_service.dart';

class RepairLedgerService {
  /// ينشئ قيود دفتر الأستاذ عند حفظ ملف إصلاح
  static Future<void> createLedgerEntryForRepair(Repair repair) async {
    final db = await DBService.database;

    if (repair.isLedgerSynced) return;

    final total = repair.totalFileValue;
    final paid = repair.totalPaidAmount;
    final now = DateTime.now().toIso8601String();
    final customerName = repair.beneficiaryName;

    // إيراد إصلاح (ذمم ↔ إيرادات)
    if (total > 0) {
      await LedgerDatabaseService.insertEntry(
        LedgerEntry(
          date: now,
          description: 'إيراد إصلاح ($customerName)',
          debitAccount: 'العملاء',
          creditAccount: 'الإيرادات',
          amount: total,
          referenceType: 'repair',
          referenceId: repair.id,
          isApproved: true,
        ),
      );
    }

    // تحصيل فعلي (صندوق ↔ العملاء)
    if (paid > 0) {
      await LedgerDatabaseService.insertEntry(
        LedgerEntry(
          date: now,
          description: 'دفعة من $customerName',
          debitAccount: 'الصندوق',
          creditAccount: 'العملاء',
          amount: paid,
          referenceType: 'repair',
          referenceId: repair.id,
          isApproved: true,
        ),
      );
    }

    // علامة مزامنة
    await db.update(
      'repairs',
      {'isLedgerSynced': 1},
      where: 'id = ?',
      whereArgs: [repair.id],
    );
  }

  /// Alias للتوافق مع استدعاءات قديمة
  static Future<void> createLedgerEntriesForRepair(Repair repair) {
    return createLedgerEntryForRepair(repair);
  }

  static Future<void> deleteLedgerEntriesForRepair(String repairId) async {
    await LedgerDatabaseService.deleteEntriesByReference('repair', repairId);
  }
}
