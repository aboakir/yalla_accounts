// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/providers/supplier_payables_provider.dart
// Provider ذمم الموردين — النسخة النهائية
// -----------------------------------------------------------------------------
// - يجلب ذمم كل الموردين
// - يجلب ذمم مورد واحد
// - يعطيك total / paid / remain بطريقة جاهزة
// - مع Riverpod
// -----------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

final supplierPayablesProvider =
    FutureProvider<List<SupplierPayableSummary>>((ref) async {
  final db = await DBService.database;

  final suppliers = await db.rawQuery("""
    SELECT id, pid, name
    FROM suppliers
    ORDER BY name ASC
  """);

  final List<SupplierPayableSummary> list = [];

  for (final s in suppliers) {
    final id = s['id'].toString();
    final pid = s['pid'].toString();
    final name = s['name'].toString();

    final invoices = await db.rawQuery("""
      SELECT id, total
      FROM purchase_invoices
      WHERE supplier_id = ?
    """, [id]);

    double total = 0;
    double paid = 0;

    for (final inv in invoices) {
      final invoiceId = inv['id'].toString();
      final t = (inv['total'] as num?)?.toDouble() ?? 0.0;
      total += t;

      final pays = await db.rawQuery("""
        SELECT SUM(amount) AS paid
        FROM purchase_payments
        WHERE invoice_id = ?
      """, [invoiceId]);

      paid += (pays.first['paid'] as num?)?.toDouble() ?? 0.0;
    }

    list.add(
      SupplierPayableSummary(
        supplierId: id,
        supplierPid: pid,
        supplierName: name,
        total: total,
        paid: paid,
        remain: total - paid,
      ),
    );
  }

  return list;
});

/// Provider ذمم مورد واحد
final singleSupplierPayablesProvider =
    FutureProvider.family<List<SupplierInvoiceRow>, String>(
        (ref, supplierId) async {
  final db = await DBService.database;

  final invoices = await db.rawQuery("""
    SELECT id, date, total
    FROM purchase_invoices
    WHERE supplier_id = ?
    ORDER BY date DESC
  """, [supplierId]);

  final List<SupplierInvoiceRow> rows = [];

  for (final inv in invoices) {
    final id = inv['id'].toString();
    final total = (inv['total'] as num?)?.toDouble() ?? 0.0;

    final pays = await db.rawQuery("""
      SELECT SUM(amount) AS paid
      FROM purchase_payments
      WHERE invoice_id = ?
    """, [id]);

    final paid = (pays.first['paid'] as num?)?.toDouble() ?? 0.0;

    rows.add(
      SupplierInvoiceRow(
        invoiceId: id,
        date: inv['date'].toString(),
        total: total,
        paid: paid,
        remain: total - paid,
      ),
    );
  }

  return rows;
});

// -----------------------------------------------------------------------------
// 🧱 الموديلات
// -----------------------------------------------------------------------------

class SupplierPayableSummary {
  final String supplierId;
  final String supplierPid;
  final String supplierName;
  final double total;
  final double paid;
  final double remain;

  SupplierPayableSummary({
    required this.supplierId,
    required this.supplierPid,
    required this.supplierName,
    required this.total,
    required this.paid,
    required this.remain,
  });
}

class SupplierInvoiceRow {
  final String invoiceId;
  final String date;
  final double total;
  final double paid;
  final double remain;

  SupplierInvoiceRow({
    required this.invoiceId,
    required this.date,
    required this.total,
    required this.paid,
    required this.remain,
  });
}
