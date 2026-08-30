// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/models/supplier.dart
// Supplier Model — FINAL SAFE VERSION
// -----------------------------------------------------------------------------
// - متوافق 100% مع DBService وعمليات Supplier CRUD
// - يعالج null issues في phone / address
// - يضمن وجود pid في toMap()
// - لا يسبب أي تعارض مع الشاشات القائمة أو الجديدة
// -----------------------------------------------------------------------------

class Supplier {
  final String id;
  final String pid;

  final String name;
  final String phone;
  final String address;

  Supplier({
    required this.id,
    required this.pid,
    required this.name,
    this.phone = '',
    this.address = '',
  });

  Supplier copyWith({
    String? id,
    String? pid,
    String? name,
    String? phone,
    String? address,
  }) {
    return Supplier(
      id: id ?? this.id,
      pid: pid ?? this.pid,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
    );
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id']?.toString() ?? '',
      pid: map['pid']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pid': pid,
      'name': name.trim(),
      'phone': phone,
      'address': address,
    };
  }
}
