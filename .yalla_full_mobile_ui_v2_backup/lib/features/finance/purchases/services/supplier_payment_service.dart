// -----------------------------------------------------------------------------
// 📁 supplier_payment_service.dart — FINAL v51
//
// نظام سداد مورد متوافق بالكامل مع قاعدة البيانات الجديدة:
// ✔ suppliers(id, name)
// ✔ purchase_invoices
// ✔ purchase_payments
// ✔ GL posting حقيقي
//
// الحسابات:
// Dr 2200.S{id}
// Cr 1000 أو 1010
// -----------------------------------------------------------------------------

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';

class SupplierPaymentService {
  static const String _ACC_CASH = "1000";
  static const String _ACC_BANK = "1010";

  // normalize method
  static String _normalize(String? m) {
    final s = (m ?? "").toLowerCase().trim();
    if (s.contains("bank") || s.contains("بنك") || s.contains("حوالة")) {
      return "bank";
    }
    return "cash";
  }

  static double _round(num v) => double.parse(v.toStringAsFixed(2));

  // ---------------------------------------------------------------------------
  // POST GL ONLY
  // ---------------------------------------------------------------------------
  static Future<int> postGL({
    required int supplierId,
    required double amount,
    required DateTime date,
    required String method,
    String? note,
    String? sourceId, // optional idempotency
  }) async {
    if (amount <= 0) throw "Amount must be > 0";

    final norm = _normalize(method);
    final amt = _round(amount);

    // حساب المورد → 2200.S{id}
    final supplierAcc =
        await DBService.ensureSupplierAccount(supplierId.toString());

    // كاش أو بنك
    final creditAcc = await DBService.getAccountIdByCode(
      norm == "bank" ? _ACC_BANK : _ACC_CASH,
    );

    if (creditAcc == null) {
      throw "Missing account ${norm == 'bank' ? _ACC_BANK : _ACC_CASH}";
    }

    final key = sourceId ?? "SUPPAY-$supplierId-${date.toIso8601String()}-$amt";

    // idempotency
    final reused =
        await DBService.getGlEntryIdBySource("SUPPLIER_PAYMENT", key);
    if (reused != null) return reused;

    final glId = await DBService.postEntryGL(
      date: date,
      source: "SUPPLIER_PAYMENT",
      sourceId: key,
      ref: "سداد مورد",
      note: note,
      lines: [
        {
          "account_id": supplierAcc,
          "debit": amt,
          "credit": 0.0,
          "party_type": "SUPPLIER",
          "party_id": supplierId,
        },
        {
          "account_id": creditAcc,
          "debit": 0.0,
          "credit": amt,
        }
      ],
    );

    return glId;
  }

  // ---------------------------------------------------------------------------
  // INSERT PAYMENT + GL
  // ---------------------------------------------------------------------------
  static Future<int> insertAndPost({
    required int supplierId,
    required double amount,
    required DateTime date,
    required String method,
    String? note,
  }) async {
    final db = await DBService.database;
    final amt = _round(amount);

    // create key
    final payId = "SUPPAY-$supplierId-${date.toIso8601String()}-$amt";

    return await db.transaction<int>((txn) async {
      // 1) insert payment into purchase_payments
      await txn.insert(
        "purchase_payments",
        {
          "id": payId,
          "supplier_id": supplierId,
          "amount": amt,
          "date": date.toIso8601String(),
          "method": _normalize(method),
          "note": note,
          "gl_entry_id": null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      // 2) GL posting
      final glId = await postGL(
        supplierId: supplierId,
        amount: amt,
        date: date,
        method: method,
        note: note,
        sourceId: payId,
      );

      // 3) update payment with gl_entry_id
      await txn.update(
        "purchase_payments",
        {"gl_entry_id": glId},
        where: "id = ?",
        whereArgs: [payId],
      );

      return glId;
    });
  }

  // ---------------------------------------------------------------------------
  // REVERSE PAYMENT
  // ---------------------------------------------------------------------------
  static Future<int> reverse(String paymentId) async {
    final db = await DBService.database;

    final r = await db.query(
      "purchase_payments",
      columns: ["gl_entry_id"],
      where: "id = ?",
      whereArgs: [paymentId],
      limit: 1,
    );

    if (r.isEmpty) throw "Payment not found";

    final raw = r.first["gl_entry_id"];
    final glId = raw is int ? raw : int.tryParse("$raw") ?? 0;

    if (glId <= 0) throw "No GL entry attached";

    final revId = await DBService.reverseEntryGL(
      glId,
      note: "عكس سداد مورد ($paymentId)",
    );

    await db.update(
      "purchase_payments",
      {"status": "REVERSED"},
      where: "id = ?",
      whereArgs: [paymentId],
    );

    return revId;
  }
}
