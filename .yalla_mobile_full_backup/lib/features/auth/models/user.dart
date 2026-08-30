// 📁 lib/features/auth/models/user_model.dart

class User {
  final String id;
  final String username;
  final String email;
  final String role; // admin, manager, user
  final String status; // active, inactive, frozen, pending
  final DateTime createdAt;
  final String? phone; // يمكن إضافته لاحقًا
  final DateTime? lastLogin; // آخر تسجيل دخول

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.status = UserStatus.active,
    DateTime? createdAt,
    this.phone,
    this.lastLogin,
  }) : createdAt = createdAt ?? DateTime.now();

  /// إنشاء كائن من خريطة بيانات (Database -> Model)
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'].toString(),
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? UserRoles.readOnly,
      status: map['status'] ?? UserStatus.active,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      phone: map['phone'],
      lastLogin: map['last_login'] != null
          ? DateTime.tryParse(map['last_login'])
          : null,
    );
  }

  /// تحويل الكائن إلى خريطة بيانات (Model -> Database)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'phone': phone,
      'last_login': lastLogin?.toIso8601String(),
    };
  }

  /// نسخة محدثة لتسهيل التعديل لاحقًا
  User copyWith({
    String? id,
    String? username,
    String? email,
    String? role,
    String? status,
    DateTime? createdAt,
    String? phone,
    DateTime? lastLogin,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      phone: phone ?? this.phone,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }
}

/// أدوار المستخدمين
class UserRoles {
  static const String owner = 'owner';
  static const String manager = 'manager';
  static const String accountant = 'accountant';
  static const String cashier = 'cashier';
  static const String workshopManager = 'workshop_manager';
  static const String estimator = 'estimator';
  static const String storekeeper = 'storekeeper';
  static const String auditor = 'auditor';
  static const String readOnly = 'read_only';
}

/// حالات المستخدمين
class UserStatus {
  static const String active = 'active';
  static const String inactive = 'inactive';
  static const String frozen = 'frozen';
  static const String pending = 'pending';
}
