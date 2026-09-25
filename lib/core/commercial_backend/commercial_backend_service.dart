import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';

import 'commercial_backend_client.dart';
import 'commercial_backend_models.dart';
import 'commercial_backend_secure_store.dart';
import 'commercial_offline_lease.dart';

class CommercialBackendService {
  CommercialBackendService({
    required CommercialBackendClient client,
    CommercialBackendSecureStore? secureStore,
    DeviceIdentityService? deviceIdentityService,
  })  : _client = client,
        _secureStore = secureStore ?? CommercialBackendSecureStore(),
        _deviceIdentityService =
            deviceIdentityService ?? DeviceIdentityService();

  final CommercialBackendClient _client;
  final CommercialBackendSecureStore _secureStore;
  final DeviceIdentityService _deviceIdentityService;

  Future<RegistrationResult> registerNewCustomer({
    required String businessName,
    required String ownerName,
    required String phoneE164,
    required String countryCode,
    required String email,
  }) async {
    final identity = await _deviceIdentityService.ensureCurrent();
    final requestId = const Uuid().v4();
    final activationSecret = _randomSecret();
    final result = await _client.register(payload: {
      'business_name': businessName.trim(),
      'owner_name': ownerName.trim(),
      'phone_e164': phoneE164.trim(),
      'email': email.trim().toLowerCase(),
      'country_code': countryCode.trim().toUpperCase(),
      'installation_id': identity.installationId,
      'organization_id': identity.organizationId,
      'device_id': identity.deviceId,
      'public_key': identity.publicKeyBase64Url,
      'public_key_algorithm': 'ED25519',
      'public_key_sha256': identity.publicKeySha256,
      'platform': identity.platform,
      'device_name': identity.deviceId,
      'app_version': identity.appVersion,
      'registration_request_id': requestId,
      'activation_secret': activationSecret,
    });
    await _secureStore.savePending(
      customerCode: result.customerCode,
      requestId: requestId,
      activationSecret: activationSecret,
    );
    return result;
  }

  Future<EmailVerificationResult> verifyPendingEmail(String code) async {
    final state = await _secureStore.read();
    if (!state.hasPendingRequest) {
      throw const CommercialBackendException(
        'EMAIL_VERIFICATION_NOT_AVAILABLE',
        'No pending registration is available for email verification.',
      );
    }
    return _client.verifyEmail(
      requestId: state.requestId!,
      activationSecret: state.activationSecret!,
      code: code,
    );
  }

  Future<EmailVerificationResult> resendPendingEmailVerification() async {
    final state = await _secureStore.read();
    if (!state.hasPendingRequest) {
      throw const CommercialBackendException(
        'EMAIL_VERIFICATION_NOT_AVAILABLE',
        'No pending registration is available for email verification.',
      );
    }
    return _client.resendEmailVerification(
      requestId: state.requestId!,
      activationSecret: state.activationSecret!,
    );
  }

  Future<DeviceRequestResult> requestExistingCustomerDevice({
    required String customerCode,
  }) async {
    final identity = await _deviceIdentityService.ensureCurrent();
    final requestId = const Uuid().v4();
    final activationSecret = _randomSecret();
    final result = await _client.requestDevice(payload: {
      'customer_code': customerCode.trim(),
      'installation_id': identity.installationId,
      'organization_id': identity.organizationId,
      'device_id': identity.deviceId,
      'public_key': identity.publicKeyBase64Url,
      'public_key_algorithm': 'ED25519',
      'public_key_sha256': identity.publicKeySha256,
      'device_request_id': requestId,
      'activation_secret': activationSecret,
      'platform': identity.platform,
      'device_name': identity.deviceId,
      'app_version': identity.appVersion,
    });
    await _secureStore.savePending(
      customerCode: customerCode.trim(),
      requestId: requestId,
      activationSecret: activationSecret,
    );
    return result;
  }

  Future<DeviceStatusResult?> refreshPendingApproval() async {
    final state = await _secureStore.read();
    if (!state.hasPendingRequest) return null;
    final result = await _client.deviceStatus(
      requestId: state.requestId!,
      activationSecret: state.activationSecret!,
    );
    if (result.status == 'APPROVED' && result.deviceToken?.isNotEmpty == true) {
      await _secureStore.saveApprovedDeviceToken(result.deviceToken!);
      await _deviceIdentityService.markBound();
      await _secureStore.clearPendingSecrets();
    }
    return result;
  }

  Future<LicenseCheckResult?> checkCurrentLicense() async {
    final state = await _secureStore.read();
    if (!state.hasApprovedDevice) return null;
    final identity = await _deviceIdentityService.ensureCurrent();
    final result = await _client.licenseCheck(
      installationId: identity.installationId,
      deviceToken: state.deviceToken!,
      appVersion: identity.appVersion,
    );
    if (result.leaseToken?.isNotEmpty == true) {
      await _secureStore.saveLease(
        leaseToken: result.leaseToken!,
        serverTime: result.serverTime,
      );
    }
    return result;
  }

  Future<EntitlementCheckResult> checkEntitlement({
    required String feature,
    String action = 'WRITE',
    String? limitCode,
    int delta = 0,
  }) async {
    final state = await _secureStore.read();
    if (!state.hasApprovedDevice) {
      throw const CommercialBackendException(
        'DEVICE_NOT_AUTHORIZED',
        'This device is not authorized.',
      );
    }
    final identity = await _deviceIdentityService.ensureCurrent();
    return _client.entitlementCheck(
      installationId: identity.installationId,
      deviceToken: state.deviceToken!,
      feature: feature,
      action: action,
      limitCode: limitCode,
      delta: delta,
    );
  }

  Future<PasswordResetChallengeResult> requestPasswordReset() async {
    final state = await _secureStore.read();
    if (!state.hasApprovedDevice) {
      throw const CommercialBackendException(
        'DEVICE_NOT_AUTHORIZED',
        'This device is not authorized for password recovery.',
      );
    }
    final identity = await _deviceIdentityService.ensureCurrent();
    return _client.requestPasswordReset(
      installationId: identity.installationId,
      deviceToken: state.deviceToken!,
    );
  }

  Future<PasswordResetGrantResult> verifyPasswordReset({
    required String challengeId,
    required String code,
  }) async {
    final state = await _secureStore.read();
    if (!state.hasApprovedDevice) {
      throw const CommercialBackendException(
        'DEVICE_NOT_AUTHORIZED',
        'This device is not authorized for password recovery.',
      );
    }
    final identity = await _deviceIdentityService.ensureCurrent();
    return _client.verifyPasswordReset(
      installationId: identity.installationId,
      deviceToken: state.deviceToken!,
      challengeId: challengeId,
      code: code,
    );
  }

  Future<bool> consumePasswordReset(String resetGrant) async {
    final state = await _secureStore.read();
    if (!state.hasApprovedDevice) return false;
    final identity = await _deviceIdentityService.ensureCurrent();
    return _client.consumePasswordReset(
      installationId: identity.installationId,
      deviceToken: state.deviceToken!,
      resetGrant: resetGrant,
    );
  }

  Future<CommercialOfflineLease?> checkOfflineLease({DateTime? now}) async {
    final state = await _secureStore.read();
    if (!state.hasApprovedDevice || state.leaseToken?.isNotEmpty != true) {
      return null;
    }
    final identity = await _deviceIdentityService.ensureCurrent();
    return CommercialOfflineLease.verify(
      token: state.leaseToken!,
      deviceToken: state.deviceToken!,
      expectedInstallationId: identity.installationId,
      now: (now ?? DateTime.now()).toUtc(),
      trustedServerTime: state.trustedServerTime,
    );
  }

  Future<String?> currentCustomerCode() async {
    final state = await _secureStore.read();
    final code = state.customerCode?.trim();
    return code == null || code.isEmpty ? null : code;
  }

  Future<CommercialRegistrationState> localState() async {
    final state = await _secureStore.read();
    if (state.hasApprovedDevice) return CommercialRegistrationState.registered;
    if (state.hasPendingRequest) return CommercialRegistrationState.pending;
    return CommercialRegistrationState.unregistered;
  }

  Future<void> resetLocalCommercialIdentity() => _secureStore.clearAll();

  static String _randomSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
