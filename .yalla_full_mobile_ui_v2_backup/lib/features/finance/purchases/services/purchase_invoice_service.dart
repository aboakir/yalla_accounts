// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/services/purchase_invoice_service.dart
// PurchaseInvoiceService — FINAL v51 COMPATIBLE
// -----------------------------------------------------------------------------
// • إنشاء فاتورة مشتريات + السطور
// • حساب الإجمالي
// • GL Posting كامل
// • النظام الجديد يعتمد فقط:
//     supplier_id (int)
//     بدون supplierPid / supplierName
// • party_id في GL = supplierId (int)
// -----------------------------------------------------------------------------

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';

class PurchaseInvoiceService {
  static const _tableHeader = "purchase_invoices";
  static const _tableLines = "purchase_invoice_lines";

  // حسابات GL
  static const _ACC_EXP_PURCHASE = "5900"; // مصاريف شراء
  static const _ACC_CASH = "1000";
  static const _ACC_BANK = "1010";
  static const _ACC_AP_ROOT = "2200"; // الموردين

  // -----------------------------------------------------------------------------
  // CREATE INVOICE (HEADER + LINES + GL)
  // -----------------------------------------------------------------------------
  static Future<String> createInvoice({
    required int supplierId,
    required DateTime date,
    required String? note,
    required List<Map<String, dynamic>> items, // [{item_name, qty, price}]
    String purchaseType = "OTHER",
    String? method, // cash / bank / credit
  }) async {
    final db = await DBService.database;
    final invoiceId = const Uuid().v4();

    // ---------------------------------------------------------------------------
    // 1) حساب إجمالي البنود
    // ---------------------------------------------------------------------------
    double total = 0;
    for (var it in items) {
      final qty = (it["qty"] ?? 1).toDouble();
      final price = (it["price"] ?? 0).toDouble();
      total += qty * price;
    }

    // ---------------------------------------------------------------------------
    // 2) تحديد طريقة الدفع + حساب الدائن
    // ---------------------------------------------------------------------------
    final m = _normalizeMethod(method);

    final cashAcc = await _accId(db, _ACC_CASH);
    final bankAcc = await _accId(db, _ACC_BANK);
    final expenseAcc = await _accId(db, _ACC_EXP_PURCHASE);
    final apRootAcc = await _accId(db, _ACC_AP_ROOT);

    if (cashAcc == null ||
        bankAcc == null ||
        expenseAcc == null ||
        apRootAcc == null) {
      throw "Missing essential accounts: 1000 / 1010 / 5900 / 2200";
    }

    late int creditAcc;
    late String status;

    if (m == "cash") {
      creditAcc = cashAcc;
      status = "PAID";
    } else if (m == "bank") {
      creditAcc = bankAcc;
      status = "PAID";
    } else {
      // شراء على الحساب → إنشاء حساب مورد 2200.S{supplierId}
      final supplierAcc =
          await DBService.ensureSupplierAccount(supplierId.toString());
      creditAcc = supplierAcc;
      status = "UNPAID";
    }

    // ---------------------------------------------------------------------------
    // 3) INSERT HEADER
    // ---------------------------------------------------------------------------
    await db.insert(_tableHeader, {
      "id": invoiceId,
      "supplier_id": supplierId,
      "date": date.toIso8601String(),
      "note": note,
      "amount_total": total,
      "paid_total": 0.0,
      "status": status,
      "purchase_type": purchaseType,
    });

    // ---------------------------------------------------------------------------
    // 4) INSERT LINES
    // ---------------------------------------------------------------------------
    for (var it in items) {
      final lineId = const Uuid().v4();
      final qty = (it["qty"] ?? 1).toDouble();
      final price = (it["price"] ?? 0).toDouble();
      final lineTotal = qty * price;

      await db.insert(_tableLines, {
        "id": lineId,
        "invoice_id": invoiceId,
        "item_name": it["item_name"],
        "qty": qty,
        "price": price,
        "total": lineTotal,
      });
    }

    // ---------------------------------------------------------------------------
    // 5) POST GL ENTRY
    // ---------------------------------------------------------------------------
    final glId = await DBService.postEntryGL(
      date: date,
      ref: invoiceId,
      source: "PURCHASE",
      sourceId: invoiceId,
      note: note,
      lines: [
        {
          // الدائن: كاش / بنك / مورد
          "account_id": creditAcc,
          "credit": total,
          "debit": 0.0,
          "party_type": m == "credit" ? "SUPPLIER" : null,
          "party_id": m == "credit" ? supplierId : null,
        },
        {
          // المدين: مصاريف شراء
          "account_id": expenseAcc,
          "debit": total,
          "credit": 0.0,
        }
      ],
    );

    await db.update(
      _tableHeader,
      {"gl_entry_id": glId},
      where: "id = ?",
      whereArgs: [invoiceId],
    );

    return invoiceId;
  }

  // -----------------------------------------------------------------------------
  // Normalize payment method
  // -----------------------------------------------------------------------------
  static String _normalizeMethod(String? m) {
    final x = (m ?? "").toLowerCase();
    if (x.contains("cash") || x.contains("نقد")) return "cash";
    if (x.contains("bank") || x.contains("بنك")) return "bank";
    return "credit";
  }

  // -----------------------------------------------------------------------------
  // Helper: read account_id from accounts table
  // -----------------------------------------------------------------------------
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
    return v is int ? v : int.tryParse(v.toString());
  }
}
