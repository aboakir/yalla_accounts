import 'package:flutter_test/flutter_test.dart';

import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/validation/periodic_license_validation_service.dart';

VerifiedLicense licenseAt(DateTime issuedAt) {
  return VerifiedLicense(
    licenseId: '11111111-1111-4111-8111-111111111111',
    organizationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    subscriptionId: '22222222-2222-4222-8222-222222222222',
    deviceId: '33333333-3333-4333-8333-333333333333',
    installationId: '44444444-4444-4444-8444-444444444444',
    issuedAt: issuedAt,
    notBefore: issuedAt,
    expiresAt: issuedAt.add(const Duration(days: 365)),
    entitlementRevision: 1,
    entitlements: const <String, Object?>{},
    validationRequiredAt: issuedAt.add(const Duration(days: 30)),
    validationGraceUntil: issuedAt.add(const Duration(days: 37)),
  );
}

void main() {
  test('validation is due at 30 days and grace expires at 37 days', () {
    final issued = DateTime.utc(2026, 1, 1);
    final window = LicenseValidationWindow.fromLicense(licenseAt(issued));

    expect(window.isDue(issued.add(const Duration(days: 29))), isFalse);
    expect(window.isDue(issued.add(const Duration(days: 30))), isTrue);
    expect(
        window.isGraceExpired(issued.add(const Duration(days: 36))), isFalse);
    expect(window.isGraceExpired(issued.add(const Duration(days: 37))), isTrue);
  });
}
