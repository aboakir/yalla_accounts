/// Legacy local license-state storage.
///
/// Signed activation state is persisted by ActivationStateRepository. These
/// methods intentionally do not persist commercial authority.
class LicenseStorage {
  LicenseStorage._();

  static const String serverAuthorityRequired = 'SERVER_AUTHORITY_REQUIRED';

  static Future<void> saveDeviceId(String deviceId) async {
    throw StateError(serverAuthorityRequired);
  }

  static Future<String?> getDeviceId() async => null;

  static Future<void> saveLicenseStatus(String status) async {
    throw StateError(serverAuthorityRequired);
  }

  static Future<String?> getLicenseStatus() async => null;

  static Future<void> clearAll() async {}
}
