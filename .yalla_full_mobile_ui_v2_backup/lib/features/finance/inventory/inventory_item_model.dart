// 📁 lib/features/finance/inventory/inventory_item_model.dart

class InventoryItem {
  final String id;
  final String name;
  final String partNumber;
  final double purchasePrice;
  final double sellingPrice;
  final int quantityInStock;
  final String unit;
  final String category;
  final DateTime lastUpdated;

  InventoryItem({
    required this.id,
    required this.name,
    required this.partNumber,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.quantityInStock,
    required this.unit,
    required this.category,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'partNumber': partNumber,
        'purchasePrice': purchasePrice,
        'sellingPrice': sellingPrice,
        'quantityInStock': quantityInStock,
        'unit': unit,
        'category': category,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory InventoryItem.fromMap(Map<String, dynamic> map) => InventoryItem(
        id: map['id'],
        name: map['name'],
        partNumber: map['partNumber'],
        purchasePrice: map['purchasePrice'],
        sellingPrice: map['sellingPrice'],
        quantityInStock: map['quantityInStock'],
        unit: map['unit'],
        category: map['category'],
        lastUpdated: DateTime.parse(map['lastUpdated']),
      );
}
