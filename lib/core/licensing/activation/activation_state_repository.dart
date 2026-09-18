import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/license_activation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/license_validation_tables.dart';

import 'license_envelope_verifier.dart';

typedef ActivationDatabaseProvider = Future<Database> Function();

class ActivationStateRepository {
  ActivationStateRepository({
    ActivationDatabaseProvider? databaseProvider,
    DeviceIdentityService? deviceIdentityService,
    LicenseEnvelopeVerifier? verifier,
  })  : _databaseProvider = databaseProvider ?? (() => DBService.database),
        _deviceIdentityService =
            deviceIdentityService ?? DeviceIdentityService(),
        _verifier = verifier ?? LicenseEnvelopeVerifier();

  final ActivationDatabaseProvider _databaseProvider;
  final DeviceIdentityService _deviceIdentityService;
  final LicenseEnvelopeVerifier _verifier;

  Future<bool> hasPersistedActivationState() async {
    final db = await _databaseProvider();
    await LicenseActivationTables.ensure(db);
    final rows = await db.query(
      'license_activation_state',
      where: 'singleton_id = 1',
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<VerifiedLicense?> loadAuthenticLicenseForCurrentInstallation({
    bool allowExpired = false,
  }) async {
    return _loadForCurrentInstallation(allowExpired: allowExpired);
  }

  Future<VerifiedLicense?> loadVerifiedLicenseForCurrentInstallation() async {
    return _loadForCurrentInstallation();
  }

  Future<VerifiedLicense?> _loadForCurrentInstallation({
    bool allowExpired = false,
  }) async {
    final db = await _databaseProvider();
    await LicenseActivationTables.ensure(db);
    // A fresh onboarding installation has no activation receipt. Do not create
    // a device identity (or touch a default database) merely to deny access.
    final receipts = await db.query('license_activation_state',
        columns: ['singleton_id'],
        where: 'singleton_id = 1 AND status = ?',
        whereArgs: ['ACTIVE'],
        limit: 1);
    if (receipts.isEmpty) return null;
    final identity = await _deviceIdentityService.ensureCurrent();

    final rows = await db.query(
      'license_activation_state',
      where: 'singleton_id = 1 AND status = ? AND organization_id = ? '
          'AND installation_id = ? AND device_id = ?',
      whereArgs: [
        'ACTIVE',
        identity.organizationId,
        identity.installationId,
        identity.deviceId,
      ],
      limit: 1,
    );
    if (rows.length != 1) return null;
    final row = rows.single;

    try {
      final envelopeRaw = jsonDecode(
        row['signed_license_envelope_json']?.toString() ?? '',
      );
      final keysetRaw = jsonDecode(
        row['verification_keyset_json']?.toString() ?? '',
      );
      if (envelopeRaw is! Map || keysetRaw is! Map) return null;
      final envelope = envelopeRaw.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final keyset = keysetRaw.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final verified = await _verifier.verify(
        envelope: envelope,
        verificationKeyset: keyset,
        identity: identity,
        requireCurrentValidity: !allowExpired,
      );
      final persistedExpiry = DateTime.tryParse(
        row['license_expires_at']?.toString() ?? '',
      );
      final matchesPersistedState =
          verified.licenseId == row['license_id']?.toString() &&
              verified.subscriptionId == row['subscription_id']?.toString() &&
              verified.entitlementRevision ==
                  (row['entitlement_revision'] as num?)?.toInt() &&
              persistedExpiry != null &&
              persistedExpiry.toUtc().isAtSameMomentAs(verified.expiresAt);
      return matchesPersistedState ? verified : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> commitVerifiedLicenseRefresh({
    required DeviceIdentity identity,
    required VerifiedLicense license,
    required String lifecycleEventId,
    required Map<String, Object?> envelope,
    required Map<String, Object?> verificationKeyset,
    required DateTime serverTime,
  }) async {
    if (lifecycleEventId.trim().isEmpty) {
      throw StateError('SEC.011 lifecycle event id is required.');
    }

    final db = await _databaseProvider();
    await LicenseActivationTables.ensure(db);
    final now = serverTime.toUtc().toIso8601String();

    final changed = await db.update(
      'license_activation_state',
      {
        'status': 'ACTIVE',
        'license_id': license.licenseId,
        'subscription_id': license.subscriptionId,
        'license_expires_at': license.expiresAt.toUtc().toIso8601String(),
        'entitlement_revision': license.entitlementRevision,
        'signed_license_envelope_json': jsonEncode(envelope),
        'verification_keyset_json': jsonEncode(verificationKeyset),
        'last_online_validation_at': now,
        'updated_at': now,
      },
      where: 'singleton_id = 1 AND organization_id = ? '
          'AND installation_id = ? AND device_id = ? '
          'AND entitlement_revision <= ? '
          "AND julianday(json_extract(signed_license_envelope_json, '\$.payload.issued_at')) <= julianday(?)",
      whereArgs: [
        identity.organizationId,
        identity.installationId,
        identity.deviceId,
        license.entitlementRevision,
        license.issuedAt.toUtc().toIso8601String(),
      ],
    );
    if (changed != 1) {
      throw StateError(
        'SEC.011 cannot refresh a missing, mismatched or newer activation receipt.',
      );
    }

    await LicenseValidationTables.projectSignedWindow(
      db,
      organizationId: license.organizationId,
      licenseId: license.licenseId,
      validationRequiredAt: license.validationRequiredAt,
      validationGraceUntil: license.validationGraceUntil,
      serverTime: serverTime,
      markSuccess: true,
    );
    await LicenseActivationTables.validate(db);
  }

  Future<bool> hasUsableActivationForCurrentInstallation() async {
    return await loadVerifiedLicenseForCurrentInstallation() != null;
  }

  Future<void> commitVerifiedActivation({
    required DeviceIdentity identity,
    required VerifiedLicense license,
    required String activationId,
    required Map<String, Object?> envelope,
    required Map<String, Object?> verificationKeyset,
    required DateTime serverTime,
  }) async {
    final db = await _databaseProvider();
    await LicenseActivationTables.ensure(db);
    final now = serverTime.toUtc().toIso8601String();

    await db.transaction((txn) async {
      final changed = await txn.update(
        'installation_identity',
        {
          'binding_state': 'BOUND',
          'bound_at': now,
          'updated_at': now,
        },
        where: 'singleton_id = 1 AND organization_id = ? '
            'AND installation_id = ? AND device_id = ?',
        whereArgs: [
          identity.organizationId,
          identity.installationId,
          identity.deviceId,
        ],
      );
      if (changed != 1) {
        throw StateError('SEC.006 failed to bind the local device identity.');
      }

      await txn.insert(
        'license_activation_state',
        {
          'singleton_id': 1,
          'organization_id': identity.organizationId,
          'installation_id': identity.installationId,
          'device_id': identity.deviceId,
          'status': 'ACTIVE',
          'activation_id': activationId,
          'license_id': license.licenseId,
          'subscription_id': license.subscriptionId,
          'license_expires_at': license.expiresAt.toUtc().toIso8601String(),
          'entitlement_revision': license.entitlementRevision,
          'signed_license_envelope_json': jsonEncode(envelope),
          'verification_keyset_json': jsonEncode(verificationKeyset),
          'activated_at': now,
          'last_online_validation_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    await LicenseValidationTables.projectSignedWindow(
      db,
      organizationId: license.organizationId,
      licenseId: license.licenseId,
      validationRequiredAt: license.validationRequiredAt,
      validationGraceUntil: license.validationGraceUntil,
      serverTime: serverTime,
      markSuccess: true,
    );
    await LicenseActivationTables.validate(db);
  }
}
