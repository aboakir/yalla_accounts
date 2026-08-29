class DeviceIdentity {
  const DeviceIdentity({
    required this.organizationId,
    required this.installationId,
    required this.deviceId,
    required this.publicKeyBase64Url,
    required this.publicKeySha256,
    required this.fingerprintSha256,
    required this.platform,
    required this.appVersion,
    required this.identityGeneration,
    required this.bindingState,
    required this.createdAt,
    this.platformVersion,
    this.boundAt,
  });

  final String organizationId;
  final String installationId;
  final String deviceId;
  final String publicKeyBase64Url;
  final String publicKeySha256;
  final String fingerprintSha256;
  final String platform;
  final String? platformVersion;
  final String appVersion;
  final int identityGeneration;
  final String bindingState;
  final DateTime createdAt;
  final DateTime? boundAt;

  bool get isBound => bindingState == 'BOUND';
  bool get isRevoked => bindingState == 'REVOKED';

  Map<String, Object?> toRegistrationPayload() => {
        'organization_id': organizationId,
        'installation_id': installationId,
        'device_id': deviceId,
        'public_key': publicKeyBase64Url,
        'public_key_algorithm': 'ED25519',
        'public_key_sha256': publicKeySha256,
        'fingerprint_hash': fingerprintSha256,
        'platform': platform,
        'platform_version': platformVersion,
        'app_version': appVersion,
        'identity_generation': identityGeneration,
      };
}

class DeviceProof {
  const DeviceProof({
    required this.deviceId,
    required this.algorithm,
    required this.signatureBase64Url,
  });

  final String deviceId;
  final String algorithm;
  final String signatureBase64Url;
}

class DeviceIdentityRecoveryRequired implements Exception {
  DeviceIdentityRecoveryRequired(this.message);
  final String message;

  @override
  String toString() => 'DeviceIdentityRecoveryRequired: $message';
}
