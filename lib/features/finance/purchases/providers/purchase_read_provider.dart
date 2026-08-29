// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/providers/purchase_read_provider.dart
// purchaseReadProvider — FINAL v51 COMPLIANT
// -----------------------------------------------------------------------------
// • يعتمد على listForDropdown() الجديدة (v51)
// • supplierLabel = اسم المورّد
// • supplierKey   = supplierId (INT)
// • لا يوجد pid أو supplier_name نهائياً
// -----------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_read_service.dart';

final purchaseReadProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await PurchaseReadService.listForDropdown();

  return rows.map((r) {
    return {
      ...r,
      'supplierKey': r['supplierId'], // INT
      'supplierLabel': r['supplierLabel'], // الاسم كما هو
    };
  }).toList();
});
