class MonthlyExpense {
  final int? id;
  final String month; // بصيغة yyyy-MM
  final double salaries;
  final double rawMaterials;
  final double electricity;
  final double rent;
  final double other;

  MonthlyExpense({
    this.id,
    required this.month,
    required this.salaries,
    required this.rawMaterials,
    required this.electricity,
    required this.rent,
    required this.other,
  });

  double get total => salaries + rawMaterials + electricity + rent + other;

  Map<String, Object?> toMap() {
    return {
      'id': id, // Object? يقبله مباشرة بدون خطأ
      'month': month,
      'salaries': salaries,
      'raw_materials': rawMaterials,
      'electricity': electricity,
      'rent': rent,
      'other': other,
    };
  }

  factory MonthlyExpense.fromMap(Map<String, dynamic> map) {
    return MonthlyExpense(
      id: map['id'] != null ? map['id'] as int : null,
      month: map['month'] as String,
      salaries: (map['salaries'] as num).toDouble(),
      rawMaterials: (map['raw_materials'] as num).toDouble(),
      electricity: (map['electricity'] as num).toDouble(),
      rent: (map['rent'] as num).toDouble(),
      other: (map['other'] as num).toDouble(),
    );
  }
}
