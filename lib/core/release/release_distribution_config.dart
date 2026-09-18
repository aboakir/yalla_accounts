/// Compile-time commercial distribution configuration.
/// Phase 17 legal documents are bundled inside Yallah Accounts.
class ReleaseDistributionConfig {
  const ReleaseDistributionConfig._();

  static const bool isStoreDistribution = bool.fromEnvironment(
    'YALLA_STORE_DISTRIBUTION',
    defaultValue: false,
  );
}
