import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';

/// Cancels a source document and its active postings in one transaction.
/// Original rows/amounts and journal entries are never removed or overwritten.
class FinancialVoidService {
  static Future<int> voidInvoice(String id,
      {required bool purchase,
      required String reason,
      Database? database}) async {
    if (reason.trim().isEmpty)
      throw ArgumentError('Cancellation reason required');
    final db = database ?? await DBService.database;
    final table = purchase ? 'purchase_invoices' : 'invoices';
    return SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn.query(table, where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty) return 0;
      final before = rows.single;
      if (['VOID', 'CANCELLED', 'REVERSED']
          .contains('${before['status']}'.toUpperCase())) return 0;
      if (purchase) {
        await RepairCostService.ensureSchema(txn);
        final allocations = await txn.rawQuery('''
          SELECT rc.id FROM repair_cost_entries rc
          JOIN purchase_invoice_lines pl ON pl.id=rc.source_line_id
          WHERE pl.invoice_id=? AND rc.status='ACTIVE'
            AND rc.source_type='PURCHASE_LINE' LIMIT 1
        ''', [id]);
        if (allocations.isNotEmpty) {
          throw StateError(
              'Reverse repair cost allocations before cancelling the purchase.');
        }
      }
      final payments = await txn.rawQuery("""
        SELECT COUNT(*) AS n FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id
        WHERE l.invoice_id=? AND e.reversal_of IS NULL
          AND UPPER(e.source) IN ('PAYMENT','PAYMENT_OUT','VOUCHER','PURCHASE_PAYMENT','PURCHASE_PAY','SUPPLIER_PAYMENT','CREDIT_ALLOCATION','CHEQUE_ENDORSE')
          AND NOT EXISTS(SELECT 1 FROM gl_entries r WHERE r.reversal_of=e.id)
      """, [id]);
      if ((payments.single['n'] as num) > 0) {
        throw StateError(
            'Reverse linked receipts/payments before cancelling this invoice.');
      }
      final entries = await txn.rawQuery("""
        SELECT id FROM gl_entries e WHERE e.source_id=?
          AND UPPER(e.source) IN (${purchase ? "'PURCHASE','PURCHASE_INVOICE'" : "'INVOICE'"})
          AND e.reversal_of IS NULL
          AND NOT EXISTS(SELECT 1 FROM gl_entries r WHERE r.reversal_of=e.id)
      """, [id]);
      final reversals = <int>[];
      for (final entry in entries) {
        reversals.add(await DBService.reverseEntryGLOn(
            txn, (entry['id'] as num).toInt(),
            note: reason));
      }
      await txn.update(
          table,
          {
            'status': 'VOID',
            'updated_at': DateTime.now().toUtc().toIso8601String()
          },
          where: 'id=?',
          whereArgs: [id]);
      await AuditTrailService.log(
          executor: txn,
          action: 'INVOICE_VOIDED',
          entityType: table,
          entityId: id,
          before: before,
          after:
              (await txn.query(table, where: 'id=?', whereArgs: [id])).single,
          reason: reason,
          metadata: {'reversal_entries': reversals});
      return 1;
    });
  }
}
