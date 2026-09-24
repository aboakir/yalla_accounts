import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_offline_lease.dart';

String leaseToken({
  required String deviceToken,
  required String installationId,
  required int issuedAt,
  required int leaseUntil,
}) {
  final payload = {
    'v': 1,
    'customer_id': 'customer-1',
    'device_id': 'device-1',
    'installation_id': installationId,
    'access_mode': 'FULL',
    'subscription_status': 'ACTIVE',
    'issued_at': issuedAt,
    'lease_until': leaseUntil,
  };
  final body =
      base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  final signature =
      Hmac(sha256, utf8.encode(deviceToken)).convert(ascii.encode(body)).bytes;
  final sig = base64UrlEncode(signature).replaceAll('=', '');
  return '$body.$sig';
}

void main() {
  const deviceToken = 'device-secret-token';
  const installationId = '11111111-1111-4111-8111-111111111111';
  final issued = DateTime.utc(2026, 9, 25, 10).millisecondsSinceEpoch ~/ 1000;
  final until = DateTime.utc(2026, 9, 25, 12).millisecondsSinceEpoch ~/ 1000;
  test('valid signed lease is accepted', () {
    final token = leaseToken(
      deviceToken: deviceToken,
      installationId: installationId,
      issuedAt: issued,
      leaseUntil: until,
    );
    final lease = CommercialOfflineLease.verify(
      token: token,
      deviceToken: deviceToken,
      expectedInstallationId: installationId,
      now: DateTime.utc(2026, 9, 25, 11),
      trustedServerTime: DateTime.utc(2026, 9, 25, 10),
    );
    expect(lease.isFull, isTrue);
    expect(lease.installationId, installationId);
  });

  test('tampering and wrong device are rejected', () {
    final token = leaseToken(
      deviceToken: deviceToken,
      installationId: installationId,
      issuedAt: issued,
      leaseUntil: until,
    );
    final tampered = '${token.substring(0, token.length - 1)}A';
    expect(
      () => CommercialOfflineLease.verify(
        token: tampered,
        deviceToken: deviceToken,
        expectedInstallationId: installationId,
        now: DateTime.utc(2026, 9, 25, 11),
      ),
      throwsFormatException,
    );
    expect(
      () => CommercialOfflineLease.verify(
        token: token,
        deviceToken: deviceToken,
        expectedInstallationId: 'other-installation',
        now: DateTime.utc(2026, 9, 25, 11),
      ),
      throwsFormatException,
    );
  });
  test('expired lease and clock rollback are rejected', () {
    final token = leaseToken(
      deviceToken: deviceToken,
      installationId: installationId,
      issuedAt: issued,
      leaseUntil: until,
    );
    expect(
      () => CommercialOfflineLease.verify(
        token: token,
        deviceToken: deviceToken,
        expectedInstallationId: installationId,
        now: DateTime.utc(2026, 9, 25, 13),
      ),
      throwsFormatException,
    );
    expect(
      () => CommercialOfflineLease.verify(
        token: token,
        deviceToken: deviceToken,
        expectedInstallationId: installationId,
        now: DateTime.utc(2026, 9, 25, 10),
        trustedServerTime: DateTime.utc(2026, 9, 25, 11),
      ),
      throwsFormatException,
    );
  });
}
