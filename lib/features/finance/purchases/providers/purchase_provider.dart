// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/providers/purchase_provider.dart
//
// PurchaseProvider — FINAL v51 COMPLIANT
// -----------------------------------------------------------------------------
// يعتمد فقط على:
//   purchase_invoices
//   purchase_invoice_lines
// بدون supplierPid / supplierName
// -----------------------------------------------------------------------------
// CREATE: عبر PurchaseInvoiceService
// READ:   عبر PurchaseReadService
// DELETE: عكس GL ثم حذف الرأس + البنود
// -----------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_read_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';

// -----------------------------------------------------------------------------
// MODEL
// -----------------------------------------------------------------------------
class Purchase {
  final String id;
  final int supplierId;
  final DateTime date;
  final double total;
  final double paidTotal;
  final String? status;
  final String? note;

  const Purchase({
    required this.id,
    required this.supplierId,
    required this.date,
    required this.total,
    required this.paidTotal,
    this.status,
    this.note,
  });

  static Purchase fromMap(Map<String, Object?> m) {
    DateTime p(Object? v) =>
        v is DateTime ? v : DateTime.tryParse('$v') ?? DateTime.now();
    double d(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

    return Purchase(
      id: '${m["id"]}',
      supplierId: i(m["supplier_id"]),
      date: p(m["date"]),
      total: d(m["amount_total"] ?? m["total_amount"]),
      paidTotal: d(m["paid_total"]),
      status: m["status"]?.toString(),
      note: m["note"]?.toString(),
    );
  }
}

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------
final purchaseProvider =
    StateNotifierProvider<PurchaseNotifier, List<Purchase>>(
  (ref) => PurchaseNotifier(),
);

// -----------------------------------------------------------------------------
// NOTIFIER
// -----------------------------------------------------------------------------
class PurchaseNotifier extends StateNotifier<List<Purchase>> {
  PurchaseNotifier() : super(const []);

  Future<Database> get _db async => DBService.database;

  // ---------------------------------------------------------------------------
  // LOAD ALL
  // ---------------------------------------------------------------------------
  Future<void> loadAll() async {
    final rows = await PurchaseReadService.listAll();
    state = rows.map(Purchase.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // LOAD BY SUPPLIER
  // ---------------------------------------------------------------------------
  Future<void> loadBySupplier(int supplierId) async {
    final rows = await PurchaseReadService.listBySupplier(supplierId);
    state = rows.map(Purchase.fromMap).toList();
  }

  Future<void> refresh() async => loadAll();

  // ---------------------------------------------------------------------------
  // ADD NEW PURCHASE INVOICE (HEADER + LINES)
  // ---------------------------------------------------------------------------
  Future<String> add({
    required int supplierId,
    required DateTime date,
    required String? note,
    required List<Map<String, dynamic>> items, // purchase lines
    String? method,
    String purchaseType = "OTHER",
  }) async {
    final invoiceId = await PurchaseInvoiceService.createInvoice(
      supplierId: supplierId,
      date: date,
      note: note,
      items: items,
      method: method,
      purchaseType: purchaseType,
    );

    await refresh();
    return invoiceId;
  }

  // ---------------------------------------------------------------------------
  // CANCEL PURCHASE → formal GL reversal → preserve source document
  // ---------------------------------------------------------------------------
  Future<void> delete(String invoiceId) async {
    final actor =
        await AuthorizationGuard.require(PermissionKeys.purchaseManage);
    final db = await _db;
    await RepairCostService.ensureSchema(db);
    final allocations = await db.rawQuery(r'''
      SELECT COUNT(*) AS c
      FROM repair_cost_entries rc
      JOIN purchase_invoice_lines pl ON pl.id = rc.source_line_id
      WHERE pl.invoice_id = ?
        AND rc.status = 'ACTIVE'
        AND rc.source_type = 'PURCHASE_LINE'
    ''', [invoiceId]);
    final allocatedCount = (allocations.first['c'] as num?)?.toInt() ?? 0;
    if (allocatedCount > 0) {
      throw StateError(
        'لا يمكن إلغاء فاتورة شراء مخصصة لملف إصلاح. اعكس تخصيصات التكلفة أولًا.',
      );
    }

    var wasPosted = false;
    await db.transaction((txn) async {
      final heads = await txn.query(
        'gl_entries',
        where:
            "UPPER(source) IN ('PURCHASE','PURCHASE_INVOICE') AND source_id=?",
        whereArgs: [invoiceId],
        orderBy: 'id',
      );
      if (heads.length > 1) {
        throw StateError(
          'Duplicate purchase posting detected for $invoiceId. '
          'Cancellation stopped for accounting audit.',
        );
      }

      if (heads.isEmpty) {
        // A never-posted draft has no accounting effect and may be removed.
        await txn.delete(
          'purchase_invoice_lines',
          where: 'invoice_id=?',
          whereArgs: [invoiceId],
        );
        await txn.delete(
          'purchase_invoices',
          where: 'id=?',
          whereArgs: [invoiceId],
        );
        return;
      }

      wasPosted = true;
      final entryId = (heads.single['id'] as num).toInt();
      final reversals = await txn.query(
        'gl_entries',
        columns: const ['id'],
        where: 'reversal_of=?',
        whereArgs: [entryId],
        limit: 1,
      );
      if (reversals.isEmpty) {
        await DBService.reverseEntryGLOn(
          txn,
          entryId,
          note: 'Cancel PURCHASE $invoiceId',
        );
      }

      // Never destroy a posted source document. Its financial rows and lines
      // remain the immutable trace behind the original posting + reversal.
      await txn.update(
        'purchase_invoices',
        {
          'status': 'CANCELLED',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [invoiceId],
      );
    });

    await AuditTrailService.log(
      actorUserId: actor?.id,
      actorRole: actor?.role,
      action:
          wasPosted ? 'PURCHASE_INVOICE_CANCELLED' : 'PURCHASE_DRAFT_DELETED',
      entityType: 'purchase_invoice',
      entityId: invoiceId,
      after: {'status': wasPosted ? 'CANCELLED' : 'DELETED_DRAFT'},
      reason: wasPosted
          ? 'Formal reversal; source document retained.'
          : 'Draft had no GL posting.',
    );

    await refresh();
  }
}
