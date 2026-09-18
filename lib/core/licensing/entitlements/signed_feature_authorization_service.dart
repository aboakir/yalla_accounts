import '../lifecycle/license_runtime_service.dart';
import 'commercial_entitlement_policy.dart';

class SignedFeatureDenied implements Exception {
  const SignedFeatureDenied(this.feature, this.reason);
  final String feature;
  final String reason;
  @override
  String toString() => 'SignedFeatureDenied($feature): $reason';
}

/// Re-verifies the current bound receipt at every operation. No cached plan,
/// local trial, UI flag, or caller-provided customer ID can grant capability.
class SignedFeatureAuthorizationService {
  SignedFeatureAuthorizationService({LicenseRuntimeService? runtimeService})
      : _runtime = runtimeService ?? LicenseRuntimeService();
  final LicenseRuntimeService _runtime;

  Future<void> requireFeature(String feature) async {
    final decision = await _runtime.refreshFromStoredLicense();
    final license = decision.license;
    if (license == null ||
        !decision.isWritable ||
        !CommercialEntitlementPolicy.isEnabled(license, feature) ||
        CommercialEntitlementPolicy.accessAllowed(license) != true) {
      throw SignedFeatureDenied(
          feature, 'Current signed authority does not permit this operation.');
    }
  }

  Future<T> execute<T>(String feature, Future<T> Function() operation) async {
    await requireFeature(feature);
    return operation();
  }
}
