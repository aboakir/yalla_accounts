import 'package:yalla_accounts/core/services/db_service.dart';
import '../../finance/purchases/services/purchase_payment_service.dart'
    as central;

class PurchasePaymentService {
  static Future<bool> payPurchase({
    required String operationId,
    required String purchaseId,
    required double amount,
    required DateTime date,
    String? supplierPid,
    String? notes,
  }) async {
    final db = await DBService.database;
    final rows = await db.query('purchase_invoices',
        columns: ['supplier_id'], where: 'id=?', whereArgs: [purchaseId]);
    if (rows.isEmpty) throw StateError('Purchase invoice not found');
    await central.PurchasePaymentService.payPurchase(
        operationId: operationId,
        purchaseId: purchaseId,
        supplierId: (rows.first['supplier_id'] as num).toInt(),
        amount: amount,
        date: date,
        method: 'CASH',
        note: notes);
    return true;
  }
}
