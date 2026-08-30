import 'package:uuid/uuid.dart';

class Subscription {
  final String id;
  final String planId;
  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final double price;

  Subscription({
    required this.id,
    required this.planId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.price,
  });

  /// إنشاء اشتراك جديد مع UUID تلقائي وحساب نهاية الاشتراك
  factory Subscription.create({
    required String planId,
    required String userId,
    required int durationDays,
    required double price,
  }) {
    final now = DateTime.now();
    return Subscription(
      id: const Uuid().v4(),
      planId: planId,
      userId: userId,
      startDate: now,
      endDate: now.add(Duration(days: durationDays)),
      price: price,
    );
  }

  /// من قاعدة البيانات إلى كائن
  factory Subscription.fromMap(Map<String, dynamic> map) {
    return Subscription(
      id: map['id'],
      planId: map['planId'],
      userId: map['userId'],
      startDate: DateTime.parse(map['startDate']),
      endDate: DateTime.parse(map['endDate']),
      price: map['price']?.toDouble() ?? 0.0,
    );
  }

  /// من كائن إلى قاعدة البيانات
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'planId': planId,
      'userId': userId,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'price': price,
    };
  }

  /// نسخ الكائن مع تعديلات اختيارية
  Subscription copyWith({
    String? id,
    String? planId,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    double? price,
  }) {
    return Subscription(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      userId: userId ?? this.userId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      price: price ?? this.price,
    );
  }

  @override
  String toString() {
    return 'Subscription(id: $id, planId: $planId, userId: $userId, start: $startDate, end: $endDate, price: $price)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Subscription &&
            id == other.id &&
            planId == other.planId &&
            userId == other.userId &&
            startDate == other.startDate &&
            endDate == other.endDate &&
            price == other.price);
  }

  @override
  int get hashCode =>
      Object.hash(id, planId, userId, startDate, endDate, price);
}
