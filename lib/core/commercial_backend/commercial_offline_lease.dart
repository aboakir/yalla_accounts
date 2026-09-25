import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'commercial_backend_models.dart';

class CommercialOfflineLease {
  const CommercialOfflineLease({
    required this.customerId,
    required this.deviceId,
    required this.installationId,
    required this.accessMode,
    required this.subscriptionStatus,
    required this.issuedAt,
    required this.leaseUntil,
    this.organizationId,
    this.subscriptionId,
    this.planCode,
    this.planName,
    this.billingPeriod = 'MONTHLY',
    this.monthlyPrice = 0,
    this.annualPrice = 0,
    this.currency = 'USD',
    this.startsAt,
    this.expiresAt,
    this.graceUntil,
    this.entitlementRevision = 0,
    this.features = const {},
    this.limits = const {},
  });

  final String customerId;
  final String deviceId;
  final String installationId;
  final String accessMode;
  final String subscriptionStatus;
  final DateTime issuedAt;
  final DateTime leaseUntil;
  final String? organizationId;
  final String? subscriptionId;
  final String? planCode;
  final String? planName;
  final String billingPeriod;
  final double monthlyPrice;
  final double annualPrice;
  final String currency;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? graceUntil;
  final int entitlementRevision;
  final Map<String, CommercialFeatureEntitlement> features;
  final Map<String, CommercialLimitEntitlement> limits;

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
        'Device clock is earlier than lease issue time.',
      );
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
      organizationId: _optionalString(map, 'organization_id'),
      subscriptionId: _optionalString(map, 'subscription_id'),
      planCode: _optionalString(map, 'plan'),
      planName: _optionalString(map, 'plan_name'),
      billingPeriod: _optionalString(map, 'billing_period') ?? 'MONTHLY',
      monthlyPrice: _double(map['monthly_price']),
      annualPrice: _double(map['annual_price']),
      currency: _optionalString(map, 'currency') ?? 'USD',
      startsAt: _date(map['starts_at']),
      expiresAt: _date(map['expires_at']),
      graceUntil: _date(map['grace_until']),
      entitlementRevision: _int(map['entitlement_revision']),
      features: _features(map['features']),
      limits: _limits(map['limits']),
    );
  }

  static Map<String, CommercialFeatureEntitlement> _features(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, CommercialFeatureEntitlement>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = (entry.value as Map).map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      out[entry.key.toString()] =
          CommercialFeatureEntitlement.fromMap(entry.key.toString(), map);
    }
    return out;
  }

  static Map<String, CommercialLimitEntitlement> _limits(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, CommercialLimitEntitlement>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = (entry.value as Map).map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      out[entry.key.toString()] =
          CommercialLimitEntitlement.fromMap(entry.key.toString(), map);
    }
    return out;
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
    final value = _optionalString(map, key);
    if (value == null) {
      throw FormatException('Missing offline lease field: $key.');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final parsed = _int(map[key], fallback: -1);
    if (parsed < 0) {
      throw FormatException('Invalid offline lease field: $key.');
    }
    return parsed;
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _date(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text.replaceFirst(' ', 'T'))?.toUtc();
  }
}
