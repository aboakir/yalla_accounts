// 📁 lib/features/clients/models/client.dart
//
// نفس السلوك السابق. بدون تغييرات تكسر. لا حاجة لإضافة account_id للموديل الآن.

class Client {
  final int? id;
  final String name;
  final String type; // "أفراد" أو "شركة تأمين"
  final String phone;
  final String email;
  final String address;
  final String notes;

  Client({
    this.id,
    required this.name,
    required this.type,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.notes = '',
  });

  factory Client.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    return Client(
      id: rawId is int ? rawId : int.tryParse(rawId?.toString() ?? ''),
      name: (map['name'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
    };
  }

  Client copyWith({
    int? id,
    String? name,
    String? type,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) {
    return Client(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
    );
  }

  bool get isInsurance => type.trim() == 'شركة تأمين';
  bool get isIndividual => type.trim() == 'أفراد';
  String get displayTypeAr => isInsurance ? 'شركة تأمين' : 'أفراد';

  String get normalizedName => _normalizeName(name);

  static String _normalizeName(String input) {
    var s = input.trim();
    s = s.replaceAll(RegExp(r'(شركة|تأمين)'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    return s;
  }

  @override
  String toString() =>
      'Client(id: $id, name: $name, type: $type, phone: $phone, email: $email, address: $address, notes: $notes)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Client &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          other.phone == phone &&
          other.email == email &&
          other.address == address &&
          other.notes == notes);

  @override
  int get hashCode => Object.hash(id, name, type, phone, email, address, notes);
}
