import 'purchase_balance_sql.dart';
// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/services/purchase_read_service.dart
//
// PurchaseReadService — نسخة نهائية v51 متوافقة بالكامل
// -----------------------------------------------------------------------------
// تعتمد على الجداول:
//   purchase_invoices
//   suppliers
//
// الحقول المستخدمة:
//   purchase_invoices.id
//   purchase_invoices.supplier_id
//   purchase_invoices.amount_total
//   purchase_invoices.paid_total
//   purchase_invoices.status
//   purchase_invoices.date
//
// توفر:
// • listAll()
// • listUnpaid()
// • listBySupplier(int supplierId)
// • listForDropdown()
// • getById()
// -----------------------------------------------------------------------------

import 'package:yalla_accounts/core/services/db/db_service.dart';

class PurchaseReadService {
  // ---------------------------------------------------------------------------
  // 1) جميع فواتير المشتريات — الأحدث أولاً
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, Object?>>> listAll() async {
    final db = await DBService.database;

    return db.rawQuery('''
      SELECT 
        pi.id,
        pi.supplier_id,
        s.name AS supplierName,
        pi.amount_total,
        ${PurchaseBalanceSql.paid('pi.id')} AS paid_total,
        CASE WHEN pi.status IN ('CANCELLED', 'VOID') THEN pi.status
          WHEN ${PurchaseBalanceSql.paid('pi.id')} >= pi.amount_total - 0.005 THEN 'PAID'
          WHEN ${PurchaseBalanceSql.paid('pi.id')} > 0.005 THEN 'PARTIAL' ELSE 'UNPAID' END AS status,
        pi.date
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON s.id = pi.supplier_id
      ORDER BY pi.date DESC, pi.id DESC
    ''');
  }

  // ---------------------------------------------------------------------------
  // 2) الفواتير غير المسددة أو المسددة جزئياً
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, Object?>>> listUnpaid() async {
    final db = await DBService.database;

    return db.rawQuery('''
      SELECT 
        pi.id,
        pi.supplier_id,
        s.name AS supplierName,
        pi.amount_total,
        ${PurchaseBalanceSql.paid('pi.id')} AS paid_total,
        CASE WHEN pi.status IN ('CANCELLED', 'VOID') THEN pi.status
          WHEN ${PurchaseBalanceSql.paid('pi.id')} >= pi.amount_total - 0.005 THEN 'PAID'
          WHEN ${PurchaseBalanceSql.paid('pi.id')} > 0.005 THEN 'PARTIAL' ELSE 'UNPAID' END AS status,
        pi.date
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON s.id = pi.supplier_id
      WHERE COALESCE(pi.status, '') NOT IN ('CANCELLED', 'VOID')
        AND pi.amount_total - ${PurchaseBalanceSql.paid('pi.id')} > 0.005
      ORDER BY pi.date DESC, pi.id DESC
    ''');
  }

  // ---------------------------------------------------------------------------
  // 3) جميع مشتريات مورد واحد عبر supplier_id
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, Object?>>> listBySupplier(
      int supplierId) async {
    final db = await DBService.database;

    return db.rawQuery('''
      SELECT 
        pi.id,
        pi.supplier_id,
        s.name AS supplierName,
        pi.amount_total,
        ${PurchaseBalanceSql.paid('pi.id')} AS paid_total,
        CASE WHEN pi.status IN ('CANCELLED', 'VOID') THEN pi.status
          WHEN ${PurchaseBalanceSql.paid('pi.id')} >= pi.amount_total - 0.005 THEN 'PAID'
          WHEN ${PurchaseBalanceSql.paid('pi.id')} > 0.005 THEN 'PARTIAL' ELSE 'UNPAID' END AS status,
        pi.date
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON s.id = pi.supplier_id
      WHERE pi.supplier_id = ?
      ORDER BY pi.date DESC, pi.id DESC
    ''', [supplierId]);
  }

  // ---------------------------------------------------------------------------
  // 4) قائمة فواتير جاهزة لاستخدامها داخل سند الصرف (Dropdown)
  // ---------------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> listForDropdown() async {
    final db = await DBService.database;

    final rows = await db.rawQuery('''
      SELECT
        pi.id,
        pi.supplier_id,
        s.name AS supplierName,
        pi.amount_total,
        ${PurchaseBalanceSql.paid('pi.id')} AS paid_total,
        CASE WHEN pi.status IN ('CANCELLED', 'VOID') THEN pi.status
          WHEN ${PurchaseBalanceSql.paid('pi.id')} >= pi.amount_total - 0.005 THEN 'PAID'
          WHEN ${PurchaseBalanceSql.paid('pi.id')} > 0.005 THEN 'PARTIAL' ELSE 'UNPAID' END AS status,
        pi.date
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON s.id = pi.supplier_id
      ORDER BY pi.date DESC, pi.id DESC
    ''');

    return rows.map((m) {
      final supplierName =
          (m["supplierName"]?.toString().trim().isNotEmpty ?? false)
              ? m["supplierName"].toString()
              : "مورّد";

      return {
        "id": m["id"],
        "supplierId": m["supplier_id"],
        "supplierLabel": supplierName,
        "amount": m["amount_total"] ?? 0.0,
        "paid": m["paid_total"] ?? 0.0,
        "status": m["status"] ?? "UNPAID",
        "date": m["date"] ?? "",
      };
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // 5) قراءة فاتورة واحدة عبر رقمها ID
  // ---------------------------------------------------------------------------
  static Future<Map<String, Object?>?> getById(String id) async {
    final db = await DBService.database;

    final r = await db.rawQuery('''
      SELECT
        pi.id,
        pi.supplier_id,
        s.name AS supplierName,
        pi.amount_total,
        ${PurchaseBalanceSql.paid('pi.id')} AS paid_total,
        CASE WHEN pi.status IN ('CANCELLED', 'VOID') THEN pi.status
          WHEN ${PurchaseBalanceSql.paid('pi.id')} >= pi.amount_total - 0.005 THEN 'PAID'
          WHEN ${PurchaseBalanceSql.paid('pi.id')} > 0.005 THEN 'PARTIAL' ELSE 'UNPAID' END AS status,
        pi.date
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON s.id = pi.supplier_id
      WHERE pi.id = ?
      LIMIT 1
    ''', [id]);

    return r.isNotEmpty ? r.first : null;
  }
}
