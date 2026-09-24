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
  });

  final String customerId;
  final String customerCode;
  final String customerStatus;
  final String deviceRequestStatus;

  bool get isPending =>
      customerStatus == 'PENDING' || deviceRequestStatus == 'PENDING';
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
  });

  final String status;
  final String? customerId;
  final String? deviceId;
  final String? installationId;
  final String? deviceToken;
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
  });

  final String customerId;
  final String customerCode;
  final String accessMode;
  final String subscriptionStatus;
  final String deviceId;
  final DateTime serverTime;
  final DateTime? leaseUntil;
  final String? leaseToken;

  bool get isFull => accessMode == 'FULL';
  bool get isReadOnly => accessMode == 'READ_ONLY';
  bool get isBlocked => accessMode == 'BLOCKED';
}
