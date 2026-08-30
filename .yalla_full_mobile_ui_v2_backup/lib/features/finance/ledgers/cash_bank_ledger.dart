class PurchaseEntry {
  final String id;
  final String supplierName;
  final String itemName;
  final String partNumber;
  final int quantity;
  final double pricePerUnit;
  final String unit;
  final DateTime date;

  PurchaseEntry({
    required this.id,
    required this.supplierName,
    required this.itemName,
    required this.partNumber,
    required this.quantity,
    required this.pricePerUnit,
    required this.unit,
    required this.date,
  });

  double get total => quantity * pricePerUnit;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplierName': supplierName,
      'itemName': itemName,
      'partNumber': partNumber,
      'quantity': quantity,
      'pricePerUnit': pricePerUnit,
      'unit': unit,
      'date': date.toIso8601String(),
    };
  }

  factory PurchaseEntry.fromMap(Map<String, dynamic> map) {
    return PurchaseEntry(
      id: map['id'],
      supplierName: map['supplierName'],
      itemName: map['itemName'],
      partNumber: map['partNumber'],
      quantity: map['quantity'],
      pricePerUnit: map['pricePerUnit'],
      unit: map['unit'],
      date: DateTime.parse(map['date']),
    );
  }
}
