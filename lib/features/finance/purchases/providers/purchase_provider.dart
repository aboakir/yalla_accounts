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
import 'package:yalla_accounts/features/finance/services/financial_void_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';

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
    await AuthorizationGuard.require(PermissionKeys.purchaseManage);
    await FinancialVoidService.voidInvoice(invoiceId,
        purchase: true, reason: 'Purchase cancelled', database: await _db);
    await refresh();
  }
}
