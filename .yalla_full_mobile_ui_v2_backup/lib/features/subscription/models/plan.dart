import 'package:uuid/uuid.dart';

class Plan {
  final String id;
  final String name;
  final double price;
  final int durationDays;
  final String? description;
  final bool isActive;

  Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.durationDays,
    this.description,
    required this.isActive,
  });

  /// إنشاء باقة جديدة مع توليد UUID تلقائي
  factory Plan.create({
    required String name,
    required double price,
    required int durationDays,
    String? description,
    bool isActive = true,
  }) {
    return Plan(
      id: const Uuid().v4(),
      name: name,
      price: price,
      durationDays: durationDays,
      description: description,
      isActive: isActive,
    );
  }

  /// تحويل من قاعدة البيانات إلى الكائن
  factory Plan.fromMap(Map<String, dynamic> map) {
    return Plan(
      id: map['id'],
      name: map['name'],
      price: map['price']?.toDouble() ?? 0.0,
      durationDays: map['durationDays'],
      description: map['description'],
      isActive: map['isActive'] == 1,
    );
  }

  /// تحويل الكائن إلى خريطة لتخزينه في قاعدة البيانات
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'durationDays': durationDays,
      'description': description,
      'isActive': isActive ? 1 : 0,
    };
  }

  /// نسخ الكائن مع إمكانية التعديل
  Plan copyWith({
    String? id,
    String? name,
    double? price,
    int? durationDays,
    String? description,
    bool? isActive,
  }) {
    return Plan(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      durationDays: durationDays ?? this.durationDays,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'Plan(id: $id, name: $name, price: $price, durationDays: $durationDays, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Plan &&
            id == other.id &&
            name == other.name &&
            price == other.price &&
            durationDays == other.durationDays &&
            description == other.description &&
            isActive == other.isActive);
  }

  @override
  int get hashCode {
    return Object.hash(id, name, price, durationDays, description, isActive);
  }

  static empty() {}
}
