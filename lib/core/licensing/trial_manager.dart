/// Legacy trial API retained so old widgets compile.
///
/// P18 removed local trial authority. A missing server-signed entitlement must
/// never be converted into a client-created trial.
class TrialManager {
  TrialManager._();

  static const String serverAuthorityRequired = 'SERVER_AUTHORITY_REQUIRED';

  static Future<void> ensureInitialized() async {}

  static Future<bool> isExpired() async => true;

  static Future<int> getRemainingHours() async => 0;

  static Future<bool> isTrialStarted() async => false;
}
