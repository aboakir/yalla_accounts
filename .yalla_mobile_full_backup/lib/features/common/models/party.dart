// 📁 lib/features/common/models/party.dart

class Party {
  final String id;
  final String name;
  final String type; // 'customer' or 'supplier'
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final DateTime createdAt;
  final bool isActive;

  Party({
    required this.id,
    required this.name,
    required this.type,
    this.phone,
    this.email,
    this.address,
    this.notes,
    DateTime? createdAt,
    this.isActive = true,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Party.fromMap(Map<String, dynamic> map) {
    return Party(
      id: map['id'].toString(),
      name: map['name'] ?? '',
      type: map['type'] ?? PartyTypes.customer,
      phone: map['phone'],
      email: map['email'],
      address: map['address'],
      notes: map['notes'],
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      isActive: map['is_active'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  Party copyWith({
    String? id,
    String? name,
    String? type,
    String? phone,
    String? email,
    String? address,
    String? notes,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return Party(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

class PartyTypes {
  static const String customer = 'customer';
  static const String supplier = 'supplier';
}
