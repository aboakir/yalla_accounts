import 'package:uuid/uuid.dart';

class PurchaseEntry {
  final String id;
  final String supplierName;
  final String itemName;
  final int quantity;
  final double pricePerUnit;
  final double total;
  final String unit;
  final DateTime date;

  PurchaseEntry({
    String? id,
    required this.supplierName,
    required this.itemName,
    required this.quantity,
    required this.pricePerUnit,
    required this.unit,
    required this.date,
    required String partNumber,
  })  : id = id ?? const Uuid().v4(),
        total = quantity * pricePerUnit;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplierName': supplierName,
      'itemName': itemName,
      'quantity': quantity,
      'pricePerUnit': pricePerUnit,
      'total': total,
      'unit': unit,
      'date': date.toIso8601String(),
    };
  }

  factory PurchaseEntry.fromMap(Map<String, dynamic> map) {
    return PurchaseEntry(
      id: map['id'],
      supplierName: map['supplierName'],
      itemName: map['itemName'],
      quantity: map['quantity'],
      pricePerUnit: map['pricePerUnit'],
      unit: map['unit'],
      date: DateTime.parse(map['date']),
      partNumber: '',
    );
  }
}
