// 📁 lib/features/repairs/models/purchase_part.dart

class PurchasePart {
  final int? id;
  final String repairId;
  final String partName;
  final double cost;
  final DateTime purchaseDate;

  PurchasePart({
    this.id,
    required this.repairId,
    required this.partName,
    required this.cost,
    required this.purchaseDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repairId': repairId,
      'partName': partName,
      'cost': cost,
      'purchaseDate': purchaseDate.toIso8601String(),
    };
  }

  factory PurchasePart.fromMap(Map<String, dynamic> map) {
    return PurchasePart(
      id: map['id'],
      repairId: map['repairId'],
      partName: map['partName'],
      cost: map['cost'],
      purchaseDate: DateTime.parse(map['purchaseDate']),
    );
  }
}
