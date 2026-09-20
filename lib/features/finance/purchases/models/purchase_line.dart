// 📁 lib/features/finance/purchases/models/purchase_line.dart
//
// PurchaseLine — سطر فاتورة شراء (v30)
// category: RAW | PARTS | TOOLS | OTHER

import 'package:meta/meta.dart';

enum PurchaseLineCategory { raw, parts, tools, other }

PurchaseLineCategory lineCatFromDb(String? v) {
  switch ((v ?? '').toUpperCase()) {
    case 'PARTS':
      return PurchaseLineCategory.parts;
    case 'TOOLS':
      return PurchaseLineCategory.tools;
    case 'OTHER':
      return PurchaseLineCategory.other;
    default:
      return PurchaseLineCategory.raw;
  }
}

String lineCatToDb(PurchaseLineCategory c) {
  switch (c) {
    case PurchaseLineCategory.raw:
      return 'RAW';
    case PurchaseLineCategory.parts:
      return 'PARTS';
    case PurchaseLineCategory.tools:
      return 'TOOLS';
    case PurchaseLineCategory.other:
      return 'OTHER';
  }
}

@immutable
class PurchaseLine {
  final String id; // UUID
  final String purchaseId; // FK → purchases.id
  final String item; // اسم الصنف
  final double qty;
  final double unitPrice;
  final double total;
  final PurchaseLineCategory category;
  final String? note;

  const PurchaseLine({
    required this.id,
    required this.purchaseId,
    required this.item,
    required this.qty,
    required this.unitPrice,
    required this.total,
    required this.category,
    this.note,
  });

  PurchaseLine copyWith({
    String? id,
    String? purchaseId,
    String? item,
    double? qty,
    double? unitPrice,
    double? total,
    PurchaseLineCategory? category,
    String? note,
  }) {
    return PurchaseLine(
      id: id ?? this.id,
      purchaseId: purchaseId ?? this.purchaseId,
      item: item ?? this.item,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      total: total ?? this.total,
      category: category ?? this.category,
      note: note ?? this.note,
    );
  }

  factory PurchaseLine.fromMap(Map<String, Object?> m) {
    final q = ((m['qty'] as num?) ?? 0).toDouble();
    final up = ((m['unit_price'] as num?) ?? 0).toDouble();
    final t = ((m['total'] as num?) ?? (q * up)).toDouble();
    return PurchaseLine(
      id: (m['id'] ?? '') as String,
      purchaseId: (m['purchase_id'] ?? '') as String,
      item: (m['item'] ?? '') as String,
      qty: q,
      unitPrice: up,
      total: t,
      category: lineCatFromDb(m['category'] as String?),
      note: m['note'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'purchase_id': purchaseId,
        'item': item,
        'qty': qty,
        'unit_price': unitPrice,
        'total': total,
        'category': lineCatToDb(category),
        'note': note,
      };
}
