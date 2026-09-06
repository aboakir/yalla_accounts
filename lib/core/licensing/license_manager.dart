/// Legacy compatibility facade.
///
/// Commercial state must come from the verified server-signed license.
enum LicenseStatus {
  serverAuthorityRequired,
}

class LicenseManager {
  static const String serverAuthorityRequired = 'SERVER_AUTHORITY_REQUIRED';

  static Future<LicenseStatus> checkStatus() async {
    throw StateError(serverAuthorityRequired);
  }
}
