// -----------------------------------------------------------------------------
// 📁 purchase_service.dart — FINAL v51
// نظام مشتريات كامل يعتمد على:
// purchase_invoices + purchase_invoice_lines + purchase_payments
// -----------------------------------------------------------------------------
// ✔ إدخال فاتورة مشتريات
// ✔ إدخال البنود
// ✔ GL Posting متكامل
// ✔ ربط الموردين عبر supplier_id فقط (بدون supplier_pid)
// ✔ لا توجد جداول قديمة (purchases / purchase_lines)
// -----------------------------------------------------------------------------

import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/accounting_gl.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';

class PurchaseService {
  PurchaseService._();
  static final PurchaseService I = PurchaseService._();

  static const _TABLE = "purchase_invoices";
  static const _LINES = "purchase_invoice_lines";

  // أكواد الحسابات مصدرها المركزي الوحيد: GL.

  // ---------------------------------------------------------------------------
  // Normalize payment method
  // ---------------------------------------------------------------------------
  static String _normalizeMethod(String? m) {
    final s = (m ?? "").trim().toLowerCase();

    if (s.contains("bank") || s.contains("حوالة") || s.contains("بنك")) {
      return "bank";
    }
    if (s.contains("cash") || s.contains("نقد") || s.contains("نقدا")) {
      return "cash";
    }
    return "credit";
  }

  // ---------------------------------------------------------------------------
  // CREATE INVOICE + LINES + GL
  // ---------------------------------------------------------------------------
  static Future<String> createInvoice({
    String? id,
    required int supplierId,
    required String supplierName,
    required DateTime date,
    required String? method,
    required List<Map<String, dynamic>> lines,
    String? note,
  }) async {
    if (lines.isEmpty) throw "لا يمكن إنشاء فاتورة بدون بنود";

    final db = await DBService.database;
    final invoiceId =
        id?.trim().isNotEmpty == true ? id!.trim() : const Uuid().v4();
    final pm = _normalizeMethod(method);

    // =======================================================================
    // حساب القيمة الحقيقية من البنود
    // =======================================================================
    final total = lines.fold<double>(
      0.0,
      (sum, row) => sum + ((row['total'] as num?)?.toDouble() ?? 0.0),
    );

    if (total <= 0) throw "المجموع يجب أن يكون أكبر من صفر";

    // =======================================================================
    // حساب GL Accounts
    // =======================================================================
    final cashAcc = await _accId(db, GL.cash);
    final bankAcc = await _accId(db, GL.bank);
    final expAcc = await _accId(db, GL.otherExpense);

    if (cashAcc == null || bankAcc == null || expAcc == null) {
      throw "Missing essential accounts";
    }

    late int creditAcc;
    late String status;

    if (pm == "cash") {
      creditAcc = cashAcc;
      status = "PAID";
    } else if (pm == "bank") {
      creditAcc = bankAcc;
      status = "PAID";
    } else {
      // المورّد → حساب 2200 + supplierId
      final supplierAcc =
          await DBService.ensureSupplierAccount(supplierId.toString());
      creditAcc = supplierAcc;
      status = "UNPAID";
    }

    // =======================================================================
    // INSERT INVOICE HEADER
    // =======================================================================
    await db.insert(
      _TABLE,
      {
        "id": invoiceId,
        "supplier_id": supplierId,
        "supplier_name": supplierName,
        "total": total,
        "date": date.toIso8601String(),
        "method": pm,
        "note": note,
        "status": status,
        "paid_total": 0.0,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    // =======================================================================
    // INSERT LINES
    // =======================================================================
    for (final row in lines) {
      await db.insert(
        _LINES,
        {
          "invoice_id": invoiceId,
          "item_name": row["item"],
          "qty": row["qty"],
          "unit_price": row["unit_price"],
          "total": row["total"],
          "category": row["category"],
          "note": row["note"],
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    // =======================================================================
    // GL ENTRY
    // =======================================================================
    final glId = await DBService.postEntryGL(
      date: date,
      ref: invoiceId,
      source: "PURCHASE_INVOICE",
      sourceId: invoiceId,
      note: note,
      lines: [
        {
          "account_id": creditAcc,
          "debit": 0.0,
          "credit": total,
        },
        {
          "account_id": expAcc,
          "debit": total,
          "credit": 0.0,
        }
      ],
    );

    await db.update(
      _TABLE,
      {"gl_entry_id": glId},
      where: "id = ?",
      whereArgs: [invoiceId],
    );

    return invoiceId;
  }

  // ---------------------------------------------------------------------------
  // Helper: Get account id
  // ---------------------------------------------------------------------------
  static Future<int?> _accId(Database db, String code) async {
    final r = await db.query(
      "accounts",
      columns: ["id"],
      where: "code = ?",
      whereArgs: [code],
      limit: 1,
    );

    if (r.isEmpty) return null;
    final v = r.first["id"];
    return (v is int) ? v : int.tryParse(v.toString());
  }

  // ---------------------------------------------------------------------------
// Backward-compatible wrapper for old APIs
// ---------------------------------------------------------------------------
  static Future<String> createAndPost({
    required int supplierId,
    required String supplierName,
    required DateTime date,
    required String method,
    required double amount,
    required String? note,
    required String purchaseType,
    required List<Map<String, dynamic>> lines,
  }) async {
    // نعيد استخدام الدالة الأصلية createInvoice
    return await createInvoice(
      supplierId: supplierId,
      supplierName: supplierName,
      date: date,
      method: method,
      note: note,
      lines: lines,
    );
  }
}
