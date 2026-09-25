import 'package:yalla_accounts/core/commercial_backend/commercial_backend_environment.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_factory.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';

import '../lifecycle/license_runtime_service.dart';
import 'commercial_entitlement_policy.dart';

class SignedFeatureDenied implements Exception {
  const SignedFeatureDenied(this.feature, this.reason, {this.status});
  final String feature;
  final String reason;
  final String? status;
  @override
  String toString() => 'SignedFeatureDenied($feature, $status): $reason';
}

/// Online PHP entitlements are authoritative. If the backend is temporarily
/// unreachable, the last valid offline lease is used fail-closed.
class SignedFeatureAuthorizationService {
  SignedFeatureAuthorizationService({LicenseRuntimeService? runtimeService})
      : _legacyRuntime = runtimeService ?? LicenseRuntimeService();

  final LicenseRuntimeService _legacyRuntime;

  Future<void> requireFeature(
    String feature, {
    String? limitCode,
    int delta = 0,
  }) async {
    if (CommercialBackendEnvironment.enabled) {
      final service = createCommercialBackendService();
      if (service != null) {
        try {
          final decision = await service.checkEntitlement(
            feature: feature,
            limitCode: limitCode,
            delta: delta,
          );
          if (!decision.allowed) {
            throw SignedFeatureDenied(
              feature,
              _message(decision.status),
              status: decision.status,
            );
          }
          return;
        } on SignedFeatureDenied {
          rethrow;
        } catch (_) {
          // Network failure only: use the last MAC-verified offline lease.
        }
      }
      try {
        CommercialBackendRuntimeAccess.requireFeature(
          feature,
          limitCode: limitCode,
          delta: delta,
        );
        return;
      } on CommercialBackendEntitlementBlocked catch (e) {
        throw SignedFeatureDenied(
          feature,
          e.userMessage,
          status: e.status,
        );
      }
    }

    final decision = await _legacyRuntime.refreshFromStoredLicense();
    final license = decision.license;
    if (license == null ||
        !decision.isWritable ||
        !CommercialEntitlementPolicy.isEnabled(license, feature) ||
        CommercialEntitlementPolicy.accessAllowed(license) != true) {
      throw SignedFeatureDenied(
        feature,
        'Current signed authority does not permit this operation.',
      );
    }
  }

  Future<T> execute<T>(
    String feature,
    Future<T> Function() operation, {
    String? limitCode,
    int delta = 0,
  }) async {
    await requireFeature(feature, limitCode: limitCode, delta: delta);
    return operation();
  }

  static String _message(String status) => switch (status) {
        'LIMIT_REACHED' => 'تم الوصول إلى حد الحزمة الحالية.',
        'READ_ONLY' => 'الاشتراك أو الميزة في وضع القراءة فقط.',
        'BLOCKED' => 'الحساب أو الاشتراك موقوف.',
        _ => 'هذه الميزة غير متاحة في الحزمة الحالية.',
      };
}
