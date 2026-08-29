// ============================================================================
// 📁 lib/features/repairs/services/edit_repair_service.dart
// P0.002 — Repair edits are operational changes, not accounting documents.
// Posted invoice/GL values stay immutable; financial changes require a formal document.
// Repair edits update the repair + history only.
// ============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

class EditRepairResult {
  final bool success;
  final double? oldValue;
  final double? newValue;
  final double? difference;

  EditRepairResult({
    required this.success,
    this.oldValue,
    this.newValue,
    this.difference,
  });
}

class EditRepairService {
  static const _uuid = Uuid();

  // ===========================================================================
  // P0.002 — Safe repair edit entry point
  // ===========================================================================
  static Future<EditRepairResult> editRepairWithAccounting({
    required String repairId,
    required Repair updatedRepair,
    required List<Map<String, dynamic>> newParts,
    required List<Map<String, dynamic>> newWorks,
    required String notes,
    required String editedBy,
  }) async {
    return await DBService.inTx((txn) async {
      // ----------------------------------------------------------------------
      // 1) Fetch original repair
      // ----------------------------------------------------------------------
      final original =
          await RepairDatabaseService.getRepairByIdTx(txn, repairId);
      if (original == null) {
        throw StateError("Repair not found ($repairId)");
      }

      // ----------------------------------------------------------------------
      // 2) Compute new total from parts + works
      // ----------------------------------------------------------------------
      double partsTotal = _sumList(newParts);
      double worksTotal = _sumList(newWorks);
      double newValue = partsTotal + worksTotal;

      final double oldValue = original.fileValue;
      final double diff = (newValue - oldValue);

      // P0.002: changing the debtor/client is a separate accounting operation.
      // The current edit screen does not change clientId, but fail closed if
      // another caller tries to do so through this service.
      if (updatedRepair.clientId != original.clientId) {
        throw StateError(
          'Cannot change repair client through editRepairWithAccounting. '
          'Client reassignment requires a dedicated audited workflow.',
        );
      }

      // ----------------------------------------------------------------------
      // 3) إذا لم تتغير القيمة → تحديث عادي بدون محاسبة
      // ----------------------------------------------------------------------
      if (diff.abs() < 0.01) {
        await _directUpdateRepair(
          txn: txn,
          repairId: repairId,
          updated: updatedRepair.copyWith(
            fileValue: newValue,
            finalApprovedAmount: newValue,
            incomeAmount: newValue,
            parts: newParts,
            works: newWorks,
          ),
        );

        await _insertHistory(
          txn: txn,
          repairId: repairId,
          oldValue: oldValue,
          newValue: newValue,
          editedBy: editedBy,
          notes: notes,
        );

        return EditRepairResult(
          success: true,
          oldValue: oldValue,
          newValue: newValue,
          difference: 0,
        );
      }

      // ----------------------------------------------------------------------
      // 4) Accounting safety policy (P0.002)
      // ----------------------------------------------------------------------
      // A repair edit is NOT an accounting document.
      //
      // Do not reverse a posted invoice/GL entry and do not create automatic
      // REPAIR_REV / REPAIR_ADJ entries. The posted invoice remains immutable.
      //
      // If the commercial amount changes after invoicing, a future formal
      // debit/credit note workflow must represent that accounting change.
      //
      // ----------------------------------------------------------------------
      // 5) Update repair (operational data only)
      // ----------------------------------------------------------------------
      final updatedMain = updatedRepair.copyWith(
        fileValue: newValue,
        finalApprovedAmount: newValue,
        incomeAmount: newValue,
        parts: newParts,
        works: newWorks,
        isLedgerSynced: false,
      );

      await _directUpdateRepair(
        txn: txn,
        repairId: repairId,
        updated: updatedMain,
      );

      // ----------------------------------------------------------------------
      // 6) Insert history
      // ----------------------------------------------------------------------
      await _insertHistory(
        txn: txn,
        repairId: repairId,
        oldValue: oldValue,
        newValue: newValue,
        editedBy: editedBy,
        notes: notes,
      );

      return EditRepairResult(
        success: true,
        oldValue: oldValue,
        newValue: newValue,
        difference: diff,
      );
    });
  }

  // ===========================================================================
  // ✔ Calculate parts/works total
  // ===========================================================================
  static double _sumList(List<Map<String, dynamic>> list) {
    double total = 0.0;
    for (final e in list) {
      final qty = (e['qty'] as num? ?? 1).toDouble();
      final price = (e['price'] as num? ?? 0).toDouble();
      total += qty * price;
    }
    return total;
  }

  // ===========================================================================
  // ✔ Update repair record directly (WITHOUT calling original updateRepair!)
  // ===========================================================================
  static Future<void> _directUpdateRepair({
    required DatabaseExecutor txn,
    required String repairId,
    required Repair updated,
  }) async {
    await txn.update(
      'repairs',
      updated.toMap(),
      where: 'id=?',
      whereArgs: [repairId],
    );
  }

  // ===========================================================================
  // ✔ Save history of modification
  // ===========================================================================
  static Future<void> _insertHistory({
    required DatabaseExecutor txn,
    required String repairId,
    required double oldValue,
    required double newValue,
    required String editedBy,
    required String notes,
  }) async {
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS repair_edit_history(
        id TEXT PRIMARY KEY,
        repair_id TEXT,
        old_value REAL,
        new_value REAL,
        difference REAL,
        edited_by TEXT,
        notes TEXT,
        created_at TEXT
      )
    ''');

    await txn.insert('repair_edit_history', {
      'id': _uuid.v4(),
      'repair_id': repairId,
      'old_value': oldValue,
      'new_value': newValue,
      'difference': newValue - oldValue,
      'edited_by': editedBy,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
