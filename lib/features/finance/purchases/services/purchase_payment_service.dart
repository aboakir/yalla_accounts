import 'package:sqflite/sqflite.dart';
import '../../../vouchers/models/voucher_payment_model.dart';
import '../../../vouchers/services/voucher_payment_service.dart';

/// All purchase payments use the atomic voucher pipeline.
class PurchasePaymentService {
  PurchasePaymentService._();

  static Future<void> insertAndPost({
    required String operationId,
    required String purchaseId,
    required int supplierId,
    required double amount,
    required DateTime date,
    required String method,
    String? notes,
    String? ref,
  }) async {
    await payPurchase(
        operationId: operationId,
        purchaseId: purchaseId,
        supplierId: supplierId,
        amount: amount,
        date: date,
        method: method,
        note: notes ?? ref);
  }

  static Future<int> payPurchase({
    required String operationId,
    required String purchaseId,
    required int supplierId,
    required double amount,
    required DateTime date,
    required String method,
    String? note,
    Database? database,
    Map<String, dynamic>? chequeDraft,
  }) async {
    if (operationId.trim().isEmpty) {
      throw ArgumentError('Operation ID required');
    }
    final posted = await VoucherPaymentService.insertAndPost(
      database: database,
      chequeDraft: chequeDraft,
      voucher: VoucherPayment(
          id: operationId,
          voucherType: 'PAYMENT',
          partyType: 'SUPPLIER',
          partyId: '$supplierId',
          amount: amount,
          currency: 'ILS',
          date: date,
          method: method.toUpperCase(),
          reference: purchaseId,
          notes: note),
      partyName: 'Supplier $supplierId',
    );
    return posted.glEntryId!;
  }
}
