/// Compile-time commercial distribution configuration.
///
/// Production store builds must pass:
///   --dart-define=YALLA_STORE_DISTRIBUTION=true
///   --dart-define=YALLA_PRIVACY_URL=https://...
///   --dart-define=YALLA_TERMS_URL=https://...
///   --dart-define=YALLA_ACCOUNT_DELETION_URL=https://...
///
/// The URLs are intentionally not hard-coded in source control.
class ReleaseDistributionConfig {
  const ReleaseDistributionConfig._();

  static const bool isStoreDistribution = bool.fromEnvironment(
    'YALLA_STORE_DISTRIBUTION',
    defaultValue: false,
  );

  static const String privacyUrl = String.fromEnvironment(
    'YALLA_PRIVACY_URL',
    defaultValue: '',
  );

  static const String termsUrl = String.fromEnvironment(
    'YALLA_TERMS_URL',
    defaultValue: '',
  );

  static const String accountDeletionUrl = String.fromEnvironment(
    'YALLA_ACCOUNT_DELETION_URL',
    defaultValue: '',
  );

  static Uri? httpsUri(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority) {
      return null;
    }
    return uri;
  }

  static bool get hasPrivacyUrl => httpsUri(privacyUrl) != null;
  static bool get hasTermsUrl => httpsUri(termsUrl) != null;
  static bool get hasAccountDeletionUrl => httpsUri(accountDeletionUrl) != null;

  static bool get hasRequiredStoreLegalUrls =>
      hasPrivacyUrl && hasTermsUrl && hasAccountDeletionUrl;
}
