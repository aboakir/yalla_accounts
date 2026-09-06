// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/services/purchase_payment_service.dart
// PurchasePaymentService — FINAL FIXED V52 VERSION
// -----------------------------------------------------------------------------
// - تحديث paid_total + remaining + status داخل purchase_invoices
// - منع السداد المكرر نهائياً
// - ربط GL بالمورد + الحسابات النقدية
// - تسجيل الدفع في جدول payments
// - تنفيذ كل شيء داخل Transaction واحدة (Atomic)
// -----------------------------------------------------------------------------

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/accounting_gl.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';

class PurchasePaymentService {
  PurchasePaymentService._();

  static const _TABLE = "purchase_invoices";
  static const _PAYMENTS = "payments";

  // أكواد الحسابات مصدرها المركزي الوحيد: GL.

  // ---------------------------------------------------------------------------
  // API — الاستدعاء من الواجهات
  // ---------------------------------------------------------------------------
  static Future<void> insertAndPost({
    required String purchaseId,
    required int supplierId,
    required double amount,
    required DateTime date,
    required String method,
    String? notes,
    String? ref,
  }) async {
    await payPurchase(
      purchaseId: purchaseId,
      supplierId: supplierId,
      amount: amount,
      date: date,
      method: method,
      note: notes ?? ref ?? "سداد فاتورة مشتريات",
    );
  }

  // ---------------------------------------------------------------------------
  // التنفيذ داخل Transaction واحدة
  // ---------------------------------------------------------------------------
  static Future<int> payPurchase({
    required String purchaseId,
    required int supplierId,
    required double amount,
    required DateTime date,
    required String method,
    String? note,
  }) async {
    if (amount <= 0) throw "Amount must be > 0";

    final db = await DBService.database;

    return await db.transaction<int>((txn) async {
      // -----------------------------------------------------------------------
      // 1) جلب بيانات الفاتورة
      // -----------------------------------------------------------------------
      final rows = await txn.rawQuery('''
        SELECT id, supplier_id, amount_total, paid_total, status, remaining
        FROM purchase_invoices
        WHERE id = ?
        LIMIT 1
      ''', [purchaseId]);

      if (rows.isEmpty) throw "Purchase not found";

      final invoice = rows.first;

      final total = (invoice["amount_total"] as num).toDouble();
      final alreadyPaid = (invoice["paid_total"] as num?)?.toDouble() ?? 0.0;

      final newPaid = alreadyPaid + amount;
      final remaining = total - newPaid;

      if (remaining < 0) {
        throw "لا يمكن دفع مبلغ أكبر من المتبقي!";
      }

      // -----------------------------------------------------------------------
      // 2) تحديد الحالة الجديدة
      // -----------------------------------------------------------------------
      String newStatus =
          newPaid >= total ? "PAID" : (newPaid > 0 ? "PARTIAL" : "UNPAID");

      // -----------------------------------------------------------------------
      // 3) تحديث الفاتورة (مهم جداً لمنع السداد المكرر)
      // -----------------------------------------------------------------------
      await txn.update(
        _TABLE,
        {
          "paid_total": newPaid,
          "remaining": remaining,
          "status": newStatus,
          "updated_at": DateTime.now().toIso8601String(),
        },
        where: "id = ?",
        whereArgs: [purchaseId],
      );

      // -----------------------------------------------------------------------
      // 4) تحديد حساب الدفع (الدائن)
      // -----------------------------------------------------------------------
      final methodNorm = method.toLowerCase().trim();
      late int creditAcc;

      if (methodNorm == "bank" || methodNorm == "transfer") {
        creditAcc =
            await _accId(txn, GL.bank) ?? (throw "Bank account 1010 missing");
      } else if (methodNorm == "cheque") {
        creditAcc = await _accId(txn, GL.receivedCheques) ??
            await _createChequeAccount(txn);
      } else {
        creditAcc =
            await _accId(txn, GL.cash) ?? (throw "Cash account 1000 missing");
      }

      // -----------------------------------------------------------------------
      // 5) P0.005 — canonical supplier AP 2200.S####
      // -----------------------------------------------------------------------
      final apSupplierAcc = await _ensureSupplierApAccount(txn, supplierId);

      // -----------------------------------------------------------------------
      // 6) قيد GL متوازن
      // -----------------------------------------------------------------------
      final glId = await DBService.postEntryGLOn(
        ex: txn,
        date: date,
        ref: purchaseId,
        source: "PURCHASE_PAYMENT",
        sourceId: "PAY-$purchaseId-${DateTime.now().millisecondsSinceEpoch}",
        note: note,
        lines: [
          {
            // Supplier payment reduces Accounts Payable.
            "account_id": apSupplierAcc,
            "debit": amount,
            "credit": 0.0,
            "party_type": "SUPPLIER",
            "party_id": supplierId,
            "invoice_id": purchaseId,
            "repair_id": null,
          },
          {
            // Cash/bank/cheques leave the business.
            "account_id": creditAcc,
            "debit": 0.0,
            "credit": amount,
            "party_type": null,
            "party_id": null,
            "invoice_id": purchaseId,
            "repair_id": null,
          },
        ],
      );

      // -----------------------------------------------------------------------
      // 7) تسجيل السداد في جدول payments
      // -----------------------------------------------------------------------
      await txn.insert(
        _PAYMENTS,
        {
          "id": const Uuid().v4(),
          "party_id": supplierId,
          "invoice_id": purchaseId,
          "repair_id": null,
          "amount": amount,
          "date": date.toIso8601String(),
          "method": methodNorm,
          "status": "posted",
          "notes": note,
          "gl_entry_id": glId,
          "isIncome": 0,
        },
      );

      return glId;
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static Future<int> _ensureSupplierApAccount(
    DatabaseExecutor txn,
    int supplierId,
  ) async {
    final suppliers = await txn.query(
      'suppliers',
      columns: ['id', 'name'],
      where: 'id = ?',
      whereArgs: [supplierId],
      limit: 1,
    );

    if (suppliers.isEmpty) {
      throw StateError('Supplier not found: $supplierId');
    }

    final code = "2200.S${supplierId.toString().padLeft(4, '0')}";
    final existing = await txn.query(
      'accounts',
      columns: ['id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final value = existing.first['id'];
      return value is int ? value : int.parse(value.toString());
    }

    return txn.insert('accounts', {
      'code': code,
      'name': suppliers.first['name']?.toString() ?? 'مورد $supplierId',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<int?> _accId(DatabaseExecutor txn, String code) async {
    final r = await txn.query(
      "accounts",
      columns: ["id"],
      where: "code = ?",
      whereArgs: [code],
      limit: 1,
    );

    if (r.isEmpty) return null;
    final v = r.first["id"];
    return v is int ? v : int.tryParse("$v");
  }

  static Future<int> _createChequeAccount(Transaction txn) async {
    return await txn.insert("accounts", {
      "code": "1020",
      "name": "حساب الشيكات",
      "type": "ASSET",
      "normal_balance": "DEBIT",
    });
  }
}
