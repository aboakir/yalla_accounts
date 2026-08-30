import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';

class LicensedUserSeatException implements Exception {
  const LicensedUserSeatException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'LicensedUserSeatException[$code]: $message';
}

class LicensedUserSeatEntitlement {
  const LicensedUserSeatEntitlement({
    required this.organizationId,
    required this.licenseId,
    required this.subscriptionId,
    required this.entitlementRevision,
    required this.maxUsers,
  });

  final String organizationId;
  final String licenseId;
  final String subscriptionId;
  final int entitlementRevision;
  final int maxUsers;
}

abstract class UserSeatEntitlementProvider {
  Future<LicensedUserSeatEntitlement> requireCurrent();
}

class LicensedUserSeatService implements UserSeatEntitlementProvider {
  LicensedUserSeatService({
    ActivationStateRepository? activationStateRepository,
  }) : _activationStateRepository =
            activationStateRepository ?? ActivationStateRepository();

  final ActivationStateRepository _activationStateRepository;

  @override
  Future<LicensedUserSeatEntitlement> requireCurrent() async {
    final license = await _activationStateRepository
        .loadVerifiedLicenseForCurrentInstallation();
    if (license == null) {
      throw const LicensedUserSeatException(
        'SIGNED_LICENSE_REQUIRED',
        'A valid signed license is required before another active user can consume a licensed seat.',
      );
    }

    return fromVerifiedLicense(license);
  }

  static LicensedUserSeatEntitlement fromVerifiedLicense(
    VerifiedLicense license,
  ) {
    final rawMaxUsers = license.entitlements['MAX_USERS'];
    if (rawMaxUsers is! int || rawMaxUsers < 1) {
      throw const LicensedUserSeatException(
        'INVALID_MAX_USERS',
        'The signed license does not contain a valid MAX_USERS entitlement.',
      );
    }

    return LicensedUserSeatEntitlement(
      organizationId: license.organizationId,
      licenseId: license.licenseId,
      subscriptionId: license.subscriptionId,
      entitlementRevision: license.entitlementRevision,
      maxUsers: rawMaxUsers,
    );
  }
}
