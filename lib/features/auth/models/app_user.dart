// lib/features/auth/models/app_user.dart

import 'package:yalla_accounts/core/security/authorization_policy.dart';

class AppUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String status;
  final DateTime createdAt;
  final String? organizationId;
  final String? identityAccountId;

  bool get isOwner => role == RoleKeys.owner;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final String? securityQuestion;
  final String? securityAnswerHash;

  final DateTime? freeTrialStart;
  final DateTime? freeTrialEnd;
  final DateTime? subscriptionDate;
  final DateTime? subscriptionEndDate;
  final double? subscriptionAmount;
  final String? paymentStatus;
  final String? paymentMethod;
  final String? paymentReceiptPath;

  final String? workshopLogoPath;
  final String? workshopAddress;
  final String? country;
  final String? province;
  final String? city;
  final String? street;
  final List<String>? phoneNumbers;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required String role,
    required this.status,
    required this.createdAt,
    this.organizationId,
    this.identityAccountId,
    bool isOwner = false,
    this.mustChangePassword = false,
    this.lastLoginAt,
    this.securityQuestion,
    this.securityAnswerHash,
    this.freeTrialStart,
    this.freeTrialEnd,
    this.subscriptionDate,
    this.subscriptionEndDate,
    this.subscriptionAmount,
    this.paymentStatus,
    this.paymentMethod,
    this.paymentReceiptPath,
    this.workshopLogoPath,
    this.workshopAddress,
    this.country,
    this.province,
    this.city,
    this.street,
    this.phoneNumbers,
  }) : role = RoleKeys.normalize(
            role); // Role is authoritative; legacy flag is serialized for compatibility.

  String? get logoPath => workshopLogoPath;
  String? get workshopName => workshopAddress;
  bool get isWorkshopOwner => isOwner;

  bool get isTrialExpired {
    if (freeTrialEnd == null) return false;
    return DateTime.now().isAfter(freeTrialEnd!);
  }

  bool get isSubscriptionValid {
    if (subscriptionEndDate == null) return false;
    return DateTime.now().isBefore(subscriptionEndDate!);
  }

  bool get isAllowed => isSubscriptionValid || !isTrialExpired;

  int get remainingDays {
    final end = subscriptionEndDate ?? freeTrialEnd;
    if (end == null) return 0;
    final diff = end.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'].toString(),
      name: map['name']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      role: map['role']?.toString() ?? 'read_only',
      status: map['status']?.toString() ?? 'active',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      organizationId: map['organization_id']?.toString(),
      identityAccountId: map['identity_account_id']?.toString(),
      isOwner: map['is_owner'] == 1 || map['is_owner'] == true,
      mustChangePassword: map['must_change_password'] == 1 ||
          map['must_change_password'] == true,
      lastLoginAt: _tryParse(map['last_login_at']),
      securityQuestion: map['security_question']?.toString(),
      securityAnswerHash: map['security_answer_hash']?.toString(),
      freeTrialStart: _tryParse(map['free_trial_start']),
      freeTrialEnd: _tryParse(map['free_trial_end']),
      subscriptionDate: _tryParse(map['subscription_date']),
      subscriptionEndDate: _tryParse(map['subscription_end_date']),
      subscriptionAmount: map['subscription_amount'] != null
          ? (map['subscription_amount'] as num).toDouble()
          : null,
      paymentStatus: map['payment_status']?.toString(),
      paymentMethod: map['payment_method']?.toString(),
      paymentReceiptPath: map['payment_receipt_path']?.toString(),
      workshopLogoPath: map['workshop_logo_path']?.toString(),
      workshopAddress: map['workshop_address']?.toString(),
      country: map['country']?.toString(),
      province: map['province']?.toString(),
      city: map['city']?.toString(),
      street: map['street']?.toString(),
      phoneNumbers: map['phone_numbers'] is String
          ? (map['phone_numbers'] as String)
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : null,
    );
  }

  static DateTime? _tryParse(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      if (organizationId != null) 'organization_id': organizationId,
      if (identityAccountId != null) 'identity_account_id': identityAccountId,
      'is_owner': isOwner ? 1 : 0,
      'must_change_password': mustChangePassword ? 1 : 0,
      'last_login_at': lastLoginAt?.toIso8601String(),
      'security_question': securityQuestion,
      'security_answer_hash': securityAnswerHash,
      'free_trial_start': freeTrialStart?.toIso8601String(),
      'free_trial_end': freeTrialEnd?.toIso8601String(),
      'subscription_date': subscriptionDate?.toIso8601String(),
      'subscription_end_date': subscriptionEndDate?.toIso8601String(),
      'subscription_amount': subscriptionAmount,
      'payment_status': paymentStatus,
      'payment_method': paymentMethod,
      'payment_receipt_path': paymentReceiptPath,
      'workshop_logo_path': workshopLogoPath,
      'workshop_address': workshopAddress,
      'country': country,
      'province': province,
      'city': city,
      'street': street,
      'phone_numbers': phoneNumbers?.join(','),
    };
  }

  Map<String, dynamic> toMapWithPassword(String hashedPassword) {
    return {
      ...toMap(),
      'password': hashedPassword,
    };
  }

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    String? status,
    DateTime? createdAt,
    String? organizationId,
    String? identityAccountId,
    bool? isOwner,
    bool? mustChangePassword,
    DateTime? lastLoginAt,
    String? securityQuestion,
    String? securityAnswerHash,
    DateTime? freeTrialStart,
    DateTime? freeTrialEnd,
    DateTime? subscriptionDate,
    DateTime? subscriptionEndDate,
    double? subscriptionAmount,
    String? paymentStatus,
    String? paymentMethod,
    String? paymentReceiptPath,
    String? workshopLogoPath,
    String? workshopAddress,
    String? country,
    String? province,
    String? city,
    String? street,
    List<String>? phoneNumbers,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      organizationId: organizationId ?? this.organizationId,
      identityAccountId: identityAccountId ?? this.identityAccountId,
      isOwner: isOwner ?? this.isOwner,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      securityQuestion: securityQuestion ?? this.securityQuestion,
      securityAnswerHash: securityAnswerHash ?? this.securityAnswerHash,
      freeTrialStart: freeTrialStart ?? this.freeTrialStart,
      freeTrialEnd: freeTrialEnd ?? this.freeTrialEnd,
      subscriptionDate: subscriptionDate ?? this.subscriptionDate,
      subscriptionEndDate: subscriptionEndDate ?? this.subscriptionEndDate,
      subscriptionAmount: subscriptionAmount ?? this.subscriptionAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentReceiptPath: paymentReceiptPath ?? this.paymentReceiptPath,
      workshopLogoPath: workshopLogoPath ?? this.workshopLogoPath,
      workshopAddress: workshopAddress ?? this.workshopAddress,
      country: country ?? this.country,
      province: province ?? this.province,
      city: city ?? this.city,
      street: street ?? this.street,
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
    );
  }
}
