enum CommercialRegistrationState { unregistered, pending, registered }

class CommercialBackendException implements Exception {
  const CommercialBackendException(
    this.code,
    this.message, {
    this.statusCode,
    this.requestId,
  });

  final String code;
  final String message;
  final int? statusCode;
  final String? requestId;

  @override
  String toString() => 'CommercialBackendException($code): $message';
}

class RegistrationResult {
  const RegistrationResult({
    required this.customerId,
    required this.customerCode,
    required this.customerStatus,
    required this.deviceRequestStatus,
    required this.emailVerified,
    required this.verificationRequired,
    this.emailMasked,
  });
  final String customerId;
  final String customerCode;
  final String customerStatus;
  final String deviceRequestStatus;
  final bool emailVerified;
  final bool verificationRequired;
  final String? emailMasked;
  bool get isPending =>
      customerStatus == 'PENDING' || deviceRequestStatus == 'PENDING';
}

class EmailVerificationResult {
  const EmailVerificationResult({
    required this.emailVerified,
    this.emailMasked,
    this.verificationRequired = false,
  });
  final bool emailVerified;
  final String? emailMasked;
  final bool verificationRequired;
}

class DeviceRequestResult {
  const DeviceRequestResult({
    required this.deviceRequestId,
    required this.status,
  });
  final String deviceRequestId;
  final String status;
}

class DeviceStatusResult {
  const DeviceStatusResult({
    required this.status,
    this.customerId,
    this.deviceId,
    this.installationId,
    this.deviceToken,
    this.emailVerified = false,
    this.emailMasked,
  });
  final String status;
  final String? customerId;
  final String? deviceId;
  final String? installationId;
  final String? deviceToken;
  final bool emailVerified;
  final String? emailMasked;
}

class CommercialFeatureEntitlement {
  const CommercialFeatureEntitlement({
    required this.code,
    required this.state,
    this.nameAr,
    this.module,
  });
  final String code;
  final String state;
  final String? nameAr;
  final String? module;

  bool get enabled => state == 'ENABLED';
  bool get readOnly => state == 'READ_ONLY';
  bool get locked => state == 'LOCKED' || state == 'BLOCKED';

  factory CommercialFeatureEntitlement.fromMap(
    String code,
    Map<String, Object?> map,
  ) {
    return CommercialFeatureEntitlement(
      code: code,
      state: (map['state']?.toString() ?? 'LOCKED').toUpperCase(),
      nameAr: map['name_ar']?.toString(),
      module: map['module']?.toString(),
    );
  }
}

class CommercialLimitEntitlement {
  const CommercialLimitEntitlement({
    required this.code,
    required this.value,
    required this.used,
    required this.periodKey,
  });
  final String code;
  final int value;
  final int used;
  final String periodKey;
  bool get unlimited => value < 0;
  bool get reached => !unlimited && used >= value;

  factory CommercialLimitEntitlement.fromMap(
    String code,
    Map<String, Object?> map,
  ) {
    return CommercialLimitEntitlement(
      code: code,
      value: _asInt(map['value']),
      used: _asInt(map['used']),
      periodKey: map['period_key']?.toString() ?? 'ALL',
    );
  }
}

class CommercialPlanOption {
  const CommercialPlanOption({
    required this.code,
    required this.name,
    required this.monthlyPrice,
    required this.annualPrice,
    required this.currency,
    this.description,
    this.features = const [],
    this.limits = const {},
  });
  final String code;
  final String name;
  final String? description;
  final double monthlyPrice;
  final double annualPrice;
  final String currency;
  final List<String> features;
  final Map<String, int> limits;

  factory CommercialPlanOption.fromMap(Map<String, Object?> map) {
    final featureRaw = map['features'];
    final limitRaw = map['limits'];
    return CommercialPlanOption(
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? map['code']?.toString() ?? '',
      description: map['description']?.toString(),
      monthlyPrice: _asDouble(map['monthly_price']),
      annualPrice: _asDouble(map['annual_price']),
      currency: map['currency']?.toString() ?? 'USD',
      features: featureRaw is List
          ? featureRaw.map((e) => e.toString()).toList(growable: false)
          : const [],
      limits: limitRaw is Map
          ? limitRaw.map<String, int>(
              (key, value) => MapEntry(key.toString(), _asInt(value)),
            )
          : const {},
    );
  }
}

class LicenseCheckResult {
  const LicenseCheckResult({
    required this.customerId,
    required this.customerCode,
    required this.accessMode,
    required this.subscriptionStatus,
    required this.deviceId,
    required this.serverTime,
    required this.leaseUntil,
    required this.leaseToken,
    this.phoneE164,
    this.businessName,
    this.ownerName,
    this.email,
    this.emailVerified = false,
    this.organizationId,
    this.subscriptionId,
    this.planCode,
    this.planName,
    this.billingPeriod = 'MONTHLY',
    this.monthlyPrice = 0,
    this.annualPrice = 0,
    this.currency = 'USD',
    this.startsAt,
    this.expiresAt,
    this.graceUntil,
    this.entitlementRevision = 0,
    this.features = const {},
    this.limits = const {},
    this.availablePlans = const [],
    this.maxUsers = 0,
    this.usersUsed = 0,
    this.maxDevices = 0,
    this.activeDevices = 0,
  });

  final String customerId;
  final String customerCode;
  final String accessMode;
  final String subscriptionStatus;
  final String deviceId;
  final DateTime serverTime;
  final DateTime? leaseUntil;
  final String? leaseToken;
  final String? phoneE164;
  final String? businessName;
  final String? ownerName;
  final String? email;
  final bool emailVerified;
  final String? organizationId;
  final String? subscriptionId;
  final String? planCode;
  final String? planName;
  final String billingPeriod;
  final double monthlyPrice;
  final double annualPrice;
  final String currency;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? graceUntil;
  final int entitlementRevision;
  final Map<String, CommercialFeatureEntitlement> features;
  final Map<String, CommercialLimitEntitlement> limits;
  final List<CommercialPlanOption> availablePlans;
  final int maxUsers;
  final int usersUsed;
  final int maxDevices;
  final int activeDevices;

  bool get isFull => accessMode == 'FULL';
  bool get isReadOnly => accessMode == 'READ_ONLY';
  bool get isBlocked => accessMode == 'BLOCKED';
}

class EntitlementCheckResult {
  const EntitlementCheckResult({
    required this.status,
  });
  final String status;
  bool get allowed => status == 'ALLOWED';
  bool get limitReached => status == 'LIMIT_REACHED';
  bool get readOnly => status == 'READ_ONLY';
  bool get planRequired => status == 'PLAN_REQUIRED';
  bool get blocked => status == 'BLOCKED';
}

class PasswordResetChallengeResult {
  const PasswordResetChallengeResult({
    required this.challengeId,
    required this.emailMasked,
    required this.expiresAt,
  });
  final String challengeId;
  final String emailMasked;
  final DateTime expiresAt;
}

class PasswordResetGrantResult {
  const PasswordResetGrantResult({
    required this.resetGrant,
    required this.expiresAt,
  });
  final String resetGrant;
  final DateTime expiresAt;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
