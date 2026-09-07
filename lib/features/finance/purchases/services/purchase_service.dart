// Stage 1 compatibility facade.
//
// Legacy callers may keep using PurchaseService, but this class no longer
// writes purchase headers/lines/GL itself. PurchaseInvoiceService is the only
// purchase-invoice writer and performs document + lines + GL atomically.

import 'purchase_invoice_service.dart';

class PurchaseService {
  PurchaseService._();
  static final PurchaseService I = PurchaseService._();

  static Future<String> createInvoice({
    String? id,
    required int supplierId,
    required String supplierName,
    required DateTime date,
    required String? method,
    required List<Map<String, dynamic>> lines,
    String? note,
  }) async {
    return PurchaseInvoiceService.createInvoice(
      id: id,
      supplierId: supplierId,
      date: date,
      note: note,
      items: lines,
      method: method,
      purchaseType: 'OTHER',
    );
  }

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
    if (lines.isEmpty) {
      throw ArgumentError('لا يمكن إنشاء فاتورة مشتريات بدون بنود');
    }
    return PurchaseInvoiceService.createInvoice(
      supplierId: supplierId,
      date: date,
      note: note,
      items: lines,
      method: method,
      purchaseType: purchaseType,
    );
  }
}
