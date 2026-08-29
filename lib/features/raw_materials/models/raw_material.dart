class RawMaterial {
  final int? id;
  final String name;
  final String supplier;
  final int quantity;
  final double unitPrice;
  final String? description;

  var sku;

  RawMaterial({
    this.id,
    required this.name,
    required this.supplier,
    required this.quantity,
    required this.unitPrice,
    this.description,
  });

  /// إنشاء نسخة جديدة مع إمكانية تعديل بعض الحقول
  RawMaterial copyWith({
    int? id,
    String? name,
    String? supplier,
    int? quantity,
    double? unitPrice,
    String? description,
  }) {
    return RawMaterial(
      id: id ?? this.id,
      name: name ?? this.name,
      supplier: supplier ?? this.supplier,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      description: description ?? this.description,
    );
  }

  /// إنشاء كائن من Map (مثل من قاعدة البيانات)
  factory RawMaterial.fromMap(Map<String, dynamic> map) {
    double parseUnitPrice(dynamic value) {
      if (value is int) return value.toDouble();
      if (value is double) return value;
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return RawMaterial(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      supplier: map['supplier'] as String? ?? '',
      quantity: map['quantity'] as int? ?? 0,
      unitPrice: parseUnitPrice(map['unit_price']),
      description: map['description'] as String?,
    );
  }

  /// تحويل الكائن إلى Map (مثل لإدخاله في قاعدة بيانات)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'supplier': supplier,
      'quantity': quantity,
      'unit_price': unitPrice,
      'description': description,
    };
  }

  /// تحويل الكائن إلى JSON
  Map<String, dynamic> toJson() => toMap();

  /// إنشاء كائن من JSON
  factory RawMaterial.fromJson(Map<String, dynamic> json) =>
      RawMaterial.fromMap(json);

  @override
  String toString() {
    return 'RawMaterial(id: $id, name: $name, supplier: $supplier, quantity: $quantity, unitPrice: $unitPrice, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RawMaterial &&
        other.id == id &&
        other.name == name &&
        other.supplier == supplier &&
        other.quantity == quantity &&
        other.unitPrice == unitPrice &&
        other.description == description;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        supplier.hashCode ^
        quantity.hashCode ^
        unitPrice.hashCode ^
        (description?.hashCode ?? 0);
  }
}
