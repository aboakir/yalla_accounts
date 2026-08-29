// 📁 lib/features/finance/purchases/models/purchase.dart
//
// Purchase Model — FINAL v51
// يتوافق مع جدول purchase_invoices الجديد
// يعتمد:
//  id
//  supplier_id (INT)
//  supplier_name (TEXT)
//  total (REAL)
//  method (TEXT)
//  purchase_type (TEXT)
//  date (TEXT)
//  note (TEXT)
//  gl_entry_id (INT)

import 'package:meta/meta.dart';

enum PurchaseMethod { cash, bank, credit }

enum PurchaseType { RAW, PARTS, TOOLS, OTHER }

// --------------------------
// METHOD MAPPERS
// --------------------------
PurchaseMethod methodFromDb(String? v) {
  switch ((v ?? '').toLowerCase()) {
    case 'cash':
      return PurchaseMethod.cash;
    case 'bank':
      return PurchaseMethod.bank;
    default:
      return PurchaseMethod.credit;
  }
}

String methodToDb(PurchaseMethod m) {
  switch (m) {
    case PurchaseMethod.cash:
      return 'cash';
    case PurchaseMethod.bank:
      return 'bank';
    case PurchaseMethod.credit:
      return 'credit';
  }
}

// --------------------------
// TYPE MAPPERS
// --------------------------
PurchaseType typeFromDb(String? v) {
  switch ((v ?? '').toUpperCase()) {
    case 'PARTS':
      return PurchaseType.PARTS;
    case 'TOOLS':
      return PurchaseType.TOOLS;
    case 'OTHER':
      return PurchaseType.OTHER;
    default:
      return PurchaseType.RAW;
  }
}

String typeToDb(PurchaseType t) {
  switch (t) {
    case PurchaseType.RAW:
      return 'RAW';
    case PurchaseType.PARTS:
      return 'PARTS';
    case PurchaseType.TOOLS:
      return 'TOOLS';
    case PurchaseType.OTHER:
      return 'OTHER';
  }
}

// --------------------------
// MODEL
// --------------------------
@immutable
class Purchase {
  final String id;
  final int? supplierId;
  final String? supplierName; // from DB (purchase_invoices.supplier_name)
  final double amount; // from DB (total)
  final PurchaseMethod method;
  final PurchaseType purchaseType;
  final DateTime date;
  final String? note;
  final int? glEntryId;

  const Purchase({
    required this.id,
    this.supplierId,
    this.supplierName,
    required this.amount,
    required this.method,
    required this.purchaseType,
    required this.date,
    this.note,
    this.glEntryId,
  });

  Purchase copyWith({
    String? id,
    int? supplierId,
    String? supplierName,
    double? amount,
    PurchaseMethod? method,
    PurchaseType? purchaseType,
    DateTime? date,
    String? note,
    int? glEntryId,
  }) {
    return Purchase(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      purchaseType: purchaseType ?? this.purchaseType,
      date: date ?? this.date,
      note: note ?? this.note,
      glEntryId: glEntryId ?? this.glEntryId,
    );
  }

  // --------------------------
  // FROM MAP (DB → MODEL)
  // --------------------------
  factory Purchase.fromMap(Map<String, Object?> m) {
    return Purchase(
      id: (m['id'] ?? '') as String,
      supplierId:
          m['supplier_id'] == null ? null : int.tryParse('${m['supplier_id']}'),
      supplierName: m['supplier_name'] as String?,
      amount: ((m['total'] as num?) ?? 0).toDouble(), // NEW
      method: methodFromDb(m['method'] as String?),
      purchaseType: typeFromDb(m['purchase_type'] as String?),
      date: DateTime.tryParse((m['date'] as String?) ?? '') ?? DateTime.now(),
      note: m['note'] as String?,
      glEntryId:
          m['gl_entry_id'] == null ? null : int.tryParse('${m['gl_entry_id']}'),
    );
  }

  // --------------------------
  // TO MAP (MODEL → DB)
  // --------------------------
  Map<String, Object?> toMap() => {
        'id': id,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'total': amount,
        'method': methodToDb(method),
        'purchase_type': typeToDb(purchaseType),
        'date': date.toIso8601String(),
        'note': note,
        'gl_entry_id': glEntryId,
      };
}
