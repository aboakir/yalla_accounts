import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';

class CommercialEntitlementDecision {
  const CommercialEntitlementDecision._({
    required this.valid,
    required this.code,
    required this.message,
  });

  final bool valid;
  final String code;
  final String message;

  const CommercialEntitlementDecision.valid()
      : this._(
          valid: true,
          code: 'ENTITLEMENTS_VALID',
          message: 'Signed commercial entitlements are valid.',
        );

  const CommercialEntitlementDecision.invalid({
    required String code,
    required String message,
  }) : this._(
          valid: false,
          code: code,
          message: message,
        );
}

/// Fail-closed client projection of the signed entitlement payload.
///
/// The licensing server remains the commercial source of truth. The client
/// only validates the signed projection and never creates or upgrades a plan.
class CommercialEntitlementPolicy {
  CommercialEntitlementPolicy._();

  static CommercialEntitlementDecision evaluate(VerifiedLicense license) {
    final entitlements = license.entitlements;

    final planCode = entitlements['PLAN_CODE'];
    if (planCode is! String ||
        planCode.trim().isEmpty ||
        planCode.length > 80) {
      return const CommercialEntitlementDecision.invalid(
        code: 'PLAN_CODE_INVALID',
        message: 'PLAN_CODE must be a non-empty signed string.',
      );
    }

    if (entitlements['ACCESS_ALLOWED'] is! bool) {
      return const CommercialEntitlementDecision.invalid(
        code: 'ACCESS_ALLOWED_INVALID',
        message: 'ACCESS_ALLOWED must be a signed boolean.',
      );
    }

    final maxUsers = entitlements['MAX_USERS'];
    if (maxUsers is! int || maxUsers < 1) {
      return const CommercialEntitlementDecision.invalid(
        code: 'MAX_USERS_INVALID',
        message: 'MAX_USERS must be a positive signed integer.',
      );
    }

    final maxDevices = entitlements['MAX_DEVICES'];
    if (maxDevices is! int || maxDevices < 1) {
      return const CommercialEntitlementDecision.invalid(
        code: 'MAX_DEVICES_INVALID',
        message: 'MAX_DEVICES must be a positive signed integer.',
      );
    }

    for (final entry in entitlements.entries) {
      final key = entry.key.trim();
      final value = entry.value;
      if (key.isEmpty) {
        return const CommercialEntitlementDecision.invalid(
          code: 'ENTITLEMENT_KEY_INVALID',
          message: 'Signed entitlement keys must not be empty.',
        );
      }
      if (key == 'PLAN_CODE') continue;
      if (key == 'ACCESS_ALLOWED') {
        if (value is! bool) {
          return const CommercialEntitlementDecision.invalid(
            code: 'ACCESS_ALLOWED_INVALID',
            message: 'ACCESS_ALLOWED must be a signed boolean.',
          );
        }
        continue;
      }
      if (key.startsWith('MAX_')) {
        if (value is! int || value < 0) {
          return const CommercialEntitlementDecision.invalid(
            code: 'ENTITLEMENT_TYPE_INVALID',
            message: 'MAX_* entitlements must be non-negative integers.',
          );
        }
        continue;
      }
      if (value is! bool) {
        return const CommercialEntitlementDecision.invalid(
          code: 'ENTITLEMENT_TYPE_INVALID',
          message: 'Feature entitlements must be booleans.',
        );
      }
    }

    return const CommercialEntitlementDecision.valid();
  }

  static bool isEnabled(VerifiedLicense license, String entitlementKey) {
    final decision = evaluate(license);
    if (!decision.valid) return false;
    return license.entitlements[entitlementKey] == true;
  }

  static int? limit(VerifiedLicense license, String entitlementKey) {
    final decision = evaluate(license);
    if (!decision.valid) return null;
    final value = license.entitlements[entitlementKey];
    return value is int ? value : null;
  }

  static String? planCode(VerifiedLicense license) {
    final decision = evaluate(license);
    if (!decision.valid) return null;
    return (license.entitlements['PLAN_CODE'] as String).trim();
  }

  static bool? accessAllowed(VerifiedLicense license) {
    final decision = evaluate(license);
    if (!decision.valid) return null;
    return license.entitlements['ACCESS_ALLOWED'] as bool;
  }
}
