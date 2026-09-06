/// Legacy local licensing facade retained only for source compatibility.
///
/// P18 authority rule: trial, activation, subscription and device entitlement
/// decisions are issued by the licensing server and verified through the
/// signed activation/lifecycle pipeline.
class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const String serverAuthorityRequired = 'SERVER_AUTHORITY_REQUIRED';

  Never _deny() => throw StateError(serverAuthorityRequired);

  Future<void> startTrialIfNeeded() async => _deny();
  Future<bool> isTrialExpired() async => _deny();

  Future<String?> activateWithCode(String code, DateTime expiryDate) async =>
      _deny();

  Future<bool> isActivated() async => _deny();
  Future<bool> isActivationExpired() async => _deny();
  Future<LicenseState> getAppState() async => _deny();
}

enum LicenseState {
  trial,
  trialExpired,
  activated,
  activationExpired,
}
