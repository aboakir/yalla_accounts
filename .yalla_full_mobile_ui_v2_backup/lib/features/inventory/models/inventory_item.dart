class InventoryItem {
  final int? id;
  final String name;
  final String category;
  final int quantity;
  final double unitPrice;
  final String? description;

  InventoryItem({
    this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unitPrice,
    this.description,
  });

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String,
      quantity: map['quantity'] as int,
      unitPrice: map['unit_price'] is int
          ? (map['unit_price'] as int).toDouble()
          : map['unit_price'] as double,
      description: map['description'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'quantity': quantity,
      'unit_price': unitPrice,
      'description': description,
    };
  }
}
