import 'dart:convert';

import 'package:crypto/crypto.dart';

class CommercialOfflineLease {
  const CommercialOfflineLease({
    required this.customerId,
    required this.deviceId,
    required this.installationId,
    required this.accessMode,
    required this.subscriptionStatus,
    required this.issuedAt,
    required this.leaseUntil,
  });

  final String customerId;
  final String deviceId;
  final String installationId;
  final String accessMode;
  final String subscriptionStatus;
  final DateTime issuedAt;
  final DateTime leaseUntil;

  bool get isFull => accessMode == 'FULL';
  bool get isReadOnly => accessMode == 'READ_ONLY';

  static CommercialOfflineLease verify({
    required String token,
    required String deviceToken,
    required String expectedInstallationId,
    required DateTime now,
    DateTime? trustedServerTime,
  }) {
    final parts = token.split('.');
    if (parts.length != 2) {
      throw const FormatException('Invalid offline lease token.');
    }
    final expected = Hmac(
      sha256,
      utf8.encode(deviceToken),
    ).convert(ascii.encode(parts[0])).bytes;
    final actual = _decode(parts[1]);

    if (!_constantTimeEquals(expected, actual)) {
      throw const FormatException('Invalid offline lease signature.');
    }

    final decoded = jsonDecode(utf8.decode(_decode(parts[0])));
    if (decoded is! Map) {
      throw const FormatException('Invalid offline lease payload.');
    }
    final map = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );

    final installationId = _requiredString(map, 'installation_id');
    if (installationId != expectedInstallationId) {
      throw const FormatException('Offline lease belongs to another device.');
    }

    final issuedAt = DateTime.fromMillisecondsSinceEpoch(
      _requiredInt(map, 'issued_at') * 1000,
      isUtc: true,
    );
    final leaseUntil = DateTime.fromMillisecondsSinceEpoch(
      _requiredInt(map, 'lease_until') * 1000,
      isUtc: true,
    );
    final current = now.toUtc();
    if (trustedServerTime != null &&
        current.isBefore(trustedServerTime.toUtc())) {
      throw const FormatException('Device clock moved behind trusted time.');
    }
    if (current.isBefore(issuedAt)) {
      throw const FormatException(
          'Device clock is earlier than lease issue time.');
    }
    if (current.isAfter(leaseUntil)) {
      throw const FormatException('Offline lease expired.');
    }

    return CommercialOfflineLease(
      customerId: _requiredString(map, 'customer_id'),
      deviceId: _requiredString(map, 'device_id'),
      installationId: installationId,
      accessMode: _requiredString(map, 'access_mode'),
      subscriptionStatus: _requiredString(map, 'subscription_status'),
      issuedAt: issuedAt,
      leaseUntil: leaseUntil,
    );
  }

  static List<int> _decode(String value) {
    final normalized =
        value.padRight(value.length + (4 - value.length % 4) % 4, '=');
    return base64Url.decode(normalized);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw FormatException('Missing offline lease field: $key.');
    }
    return value;
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw FormatException('Invalid offline lease field: $key.');
    }
    return parsed;
  }
}
