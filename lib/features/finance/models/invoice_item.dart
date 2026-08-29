// 📁 lib/features/finance/models/invoice_item.dart

class InvoiceItem {
  final String id;
  final String invoiceId;
  final String description;
  final int quantity;
  final double unitPrice;

  InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      id: map['id'].toString(),
      invoiceId: map['invoice_id'],
      description: map['description'] ?? '',
      quantity: map['quantity'] ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
    };
  }

  InvoiceItem copyWith({
    String? id,
    String? invoiceId,
    String? description,
    int? quantity,
    double? unitPrice,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}
