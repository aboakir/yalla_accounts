import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';

class LicenseVerificationException implements Exception {
  const LicenseVerificationException(this.message);
  final String message;

  @override
  String toString() => 'LicenseVerificationException: $message';
}

class VerifiedLicense {
  const VerifiedLicense({
    required this.licenseId,
    required this.organizationId,
    required this.subscriptionId,
    required this.deviceId,
    required this.installationId,
    required this.issuedAt,
    required this.notBefore,
    required this.expiresAt,
    required this.entitlementRevision,
    required this.entitlements,
    required this.validationRequiredAt,
    required this.validationGraceUntil,
    this.operationalStatus = 'ACTIVE',
  });

  final String licenseId;
  final String organizationId;
  final String subscriptionId;
  final String deviceId;
  final String installationId;
  final DateTime issuedAt;
  final DateTime notBefore;
  final DateTime expiresAt;
  final int entitlementRevision;
  final Map<String, Object?> entitlements;
  final DateTime validationRequiredAt;
  final DateTime validationGraceUntil;
  final String operationalStatus;
}

class LicenseEnvelopeVerifier {
  LicenseEnvelopeVerifier({
    Ed25519? algorithm,
    Set<String>? trustedPublicKeySha256,
  })  : _algorithm = algorithm ?? Ed25519(),
        _trustedPublicKeySha256 =
            trustedPublicKeySha256 ?? _environmentTrustedKeyHashes();

  final Ed25519 _algorithm;
  final Set<String> _trustedPublicKeySha256;

  bool get isTrustConfigured => _trustedPublicKeySha256.isNotEmpty;

  static Set<String> _environmentTrustedKeyHashes() {
    const raw = String.fromEnvironment('YALLA_LICENSE_TRUSTED_KEY_SHA256');
    return raw
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value))
        .toSet();
  }

  Future<VerifiedLicense> verify({
    required Map<String, Object?> envelope,
    required Map<String, Object?> verificationKeyset,
    required DeviceIdentity identity,
    DateTime? now,
    bool requireCurrentValidity = true,
  }) async {
    if (envelope['typ'] != 'YALLA-LICENSE' || envelope['alg'] != 'EdDSA') {
      throw const LicenseVerificationException('Unsupported license envelope.');
    }
    final kid = envelope['kid']?.toString() ?? '';
    final payloadRaw = envelope['payload'];
    if (kid.isEmpty || payloadRaw is! Map) {
      throw const LicenseVerificationException('Malformed license envelope.');
    }
    final payload = payloadRaw.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );

    final canonical = _canonicalize(payload);
    final canonicalBytes = utf8.encode(canonical);
    final payloadHash = sha256.convert(canonicalBytes).toString();
    if (payloadHash != envelope['payload_sha256']?.toString()) {
      throw const LicenseVerificationException(
          'License payload hash mismatch.');
    }

    if (verificationKeyset['issuer'] != 'yalla-licensing') {
      throw const LicenseVerificationException(
          'Untrusted verification keyset.');
    }
    final keys = verificationKeyset['keys'];
    if (keys is! List) {
      throw const LicenseVerificationException(
          'Verification keyset is malformed.');
    }
    Map<String, Object?>? key;
    for (final candidate in keys) {
      if (candidate is Map && candidate['kid']?.toString() == kid) {
        key = candidate.map<String, Object?>(
          (k, v) => MapEntry(k.toString(), v),
        );
        break;
      }
    }
    if (key == null || key['alg'] != 'EdDSA') {
      throw const LicenseVerificationException('Signing key is unavailable.');
    }
    final status = key['status']?.toString();
    if (status != 'ACTIVE' && status != 'RETIRED') {
      throw const LicenseVerificationException('Signing key is not trusted.');
    }
    if (key['revoked_at'] != null) {
      throw const LicenseVerificationException('Signing key is revoked.');
    }

    final publicBytes = _decodeBase64Url(key['public_key']?.toString() ?? '');
    if (publicBytes.length != 32) {
      throw const LicenseVerificationException('Invalid Ed25519 public key.');
    }
    final expectedKeyHash = sha256.convert(publicBytes).toString();
    if (expectedKeyHash != key['public_key_sha256']?.toString()) {
      throw const LicenseVerificationException(
          'Verification key hash mismatch.');
    }
    if (_trustedPublicKeySha256.isEmpty) {
      throw const LicenseVerificationException(
        'License verification trust anchor is not configured.',
      );
    }
    if (!_trustedPublicKeySha256.contains(expectedKeyHash)) {
      throw const LicenseVerificationException(
        'License signing key is not pinned by this build.',
      );
    }
    final signatureBytes =
        _decodeBase64Url(envelope['signature']?.toString() ?? '');
    if (signatureBytes.length != 64) {
      throw const LicenseVerificationException(
          'Invalid license signature length.');
    }
    final validSignature = await _algorithm.verify(
      canonicalBytes,
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
      ),
    );
    if (!validSignature) {
      throw const LicenseVerificationException(
          'License signature verification failed.');
    }

    _requireBinding(payload, identity);
    final issuedAt = _date(payload, 'issued_at');
    final notBefore = _date(payload, 'not_before');
    final expiresAt = _date(payload, 'expires_at');
    final keyNotBefore = DateTime.tryParse(key['not_before']?.toString() ?? '');
    if (keyNotBefore == null || issuedAt.isBefore(keyNotBefore.toUtc())) {
      throw const LicenseVerificationException(
        'License was signed before the verification key became valid.',
      );
    }
    final keyNotAfterRaw = key['not_after']?.toString();
    if (keyNotAfterRaw != null && keyNotAfterRaw.isNotEmpty) {
      final keyNotAfter = DateTime.tryParse(keyNotAfterRaw);
      if (keyNotAfter == null || !issuedAt.isBefore(keyNotAfter.toUtc())) {
        throw const LicenseVerificationException(
          'License was signed outside the verification key validity window.',
        );
      }
    }
    final current = (now ?? DateTime.now()).toUtc();
    if (requireCurrentValidity &&
        (notBefore.isAfter(current) || !expiresAt.isAfter(current))) {
      throw const LicenseVerificationException(
          'License is outside its validity window.');
    }
    if (expiresAt.isBefore(notBefore) || issuedAt.isAfter(expiresAt)) {
      throw const LicenseVerificationException(
          'License timestamps are inconsistent.');
    }

    final revision = payload['entitlement_revision'];
    if (revision is! int || revision < 0) {
      throw const LicenseVerificationException('Invalid entitlement revision.');
    }
    final entitlementsRaw = payload['entitlements'];
    if (entitlementsRaw is! Map) {
      throw const LicenseVerificationException('Invalid license entitlements.');
    }
    final entitlements = entitlementsRaw.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final hasValidationRequiredAt =
        payload.containsKey('validation_required_at');
    final hasValidationGraceUntil =
        payload.containsKey('validation_grace_until');
    if (hasValidationRequiredAt != hasValidationGraceUntil) {
      throw const LicenseVerificationException(
        'Incomplete periodic validation policy in signed license.',
      );
    }
    final validationRequiredAt = hasValidationRequiredAt
        ? _date(payload, 'validation_required_at')
        : issuedAt.add(const Duration(days: 30));
    final validationGraceUntil = hasValidationGraceUntil
        ? _date(payload, 'validation_grace_until')
        : validationRequiredAt.add(const Duration(days: 7));
    if (validationRequiredAt.isBefore(issuedAt) ||
        validationGraceUntil.isBefore(validationRequiredAt)) {
      throw const LicenseVerificationException(
        'Invalid periodic validation window in signed license.',
      );
    }

    final operationalStatus =
        (payload['operational_status']?.toString() ?? 'ACTIVE')
            .trim()
            .toUpperCase();
    const allowedOperationalStatuses = <String>{
      'ACTIVE',
      'TRIAL',
      'FROZEN',
      'EXCEPTION',
      'DEMO',
      'GRACE',
      'SUSPENDED',
      'EXPIRED',
      'REVOKED',
      'CANCELLED',
    };
    if (!allowedOperationalStatuses.contains(operationalStatus)) {
      throw const LicenseVerificationException(
        'Unsupported operational license status.',
      );
    }

    return VerifiedLicense(
      licenseId: payload['license_id']!.toString(),
      organizationId: payload['organization_id']!.toString(),
      subscriptionId: payload['subscription_id']!.toString(),
      deviceId: payload['device_id']!.toString(),
      installationId: payload['installation_id']!.toString(),
      issuedAt: issuedAt,
      notBefore: notBefore,
      expiresAt: expiresAt,
      entitlementRevision: revision,
      entitlements: Map.unmodifiable(entitlements),
      validationRequiredAt: validationRequiredAt,
      validationGraceUntil: validationGraceUntil,
      operationalStatus: operationalStatus,
    );
  }

  static void _requireBinding(
    Map<String, Object?> payload,
    DeviceIdentity identity,
  ) {
    final expected = <String, String>{
      'organization_id': identity.organizationId,
      'device_id': identity.deviceId,
      'installation_id': identity.installationId,
      'device_public_key_sha256': identity.publicKeySha256,
    };
    for (final entry in expected.entries) {
      if (payload[entry.key]?.toString() != entry.value) {
        throw LicenseVerificationException(
          'License binding mismatch: ${entry.key}.',
        );
      }
    }
    if (payload['schema_version'] != 1 ||
        payload['issuer'] != 'yalla-licensing') {
      throw const LicenseVerificationException('Unsupported license payload.');
    }
    for (final key in ['license_id', 'subscription_id']) {
      if ((payload[key]?.toString() ?? '').isEmpty) {
        throw LicenseVerificationException('Missing license field: $key.');
      }
    }
  }

  static DateTime _date(Map<String, Object?> payload, String key) {
    final parsed = DateTime.tryParse(payload[key]?.toString() ?? '');
    if (parsed == null) {
      throw LicenseVerificationException('Invalid license timestamp: $key.');
    }
    return parsed.toUtc();
  }

  /// RFC 8785-compatible canonicalization for the SEC.004 v1 payload domain.
  /// Floating-point entitlement values are intentionally rejected in v1;
  /// Yalla's current entitlement catalog uses booleans and integers.
  static String _canonicalize(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is double) {
      throw const LicenseVerificationException(
        'Floating-point license values are not supported in payload v1.',
      );
    }
    if (value is String) return jsonEncode(value);
    if (value is List) {
      return '[${value.map(_canonicalize).join(',')}]';
    }
    if (value is Map) {
      final normalized = value.map<String, Object?>(
        (key, item) => MapEntry(key.toString(), item),
      );
      final keys = normalized.keys.toList()..sort();
      final parts = <String>[];
      for (final key in keys) {
        parts.add('${jsonEncode(key)}:${_canonicalize(normalized[key])}');
      }
      return '{${parts.join(',')}}';
    }
    throw LicenseVerificationException(
      'Unsupported canonical JSON value: ${value.runtimeType}.',
    );
  }

  static List<int> _decodeBase64Url(String value) {
    try {
      final padding = List.filled((4 - value.length % 4) % 4, '=').join();
      return base64Url.decode('$value$padding');
    } catch (_) {
      throw const LicenseVerificationException('Invalid base64url data.');
    }
  }
}
