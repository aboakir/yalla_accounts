import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/entitlements/commercial_feature_catalog.dart';
import 'package:yalla_accounts/core/licensing/entitlements/signed_feature_authorization_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/subscription_access_policy.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

VerifiedLicense license(
    {String org = 'org',
    int revision = 4,
    bool enabled = true,
    String status = 'ACTIVE',
    String plan = 'PRO',
    DateTime? issued}) {
  final now = DateTime.now().toUtc();
  return VerifiedLicense(
      licenseId: 'license',
      organizationId: org,
      subscriptionId: 'sub',
      deviceId: 'device',
      installationId: 'install',
      issuedAt: issued ?? now,
      notBefore: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 30)),
      entitlementRevision: revision,
      entitlements: {
        'PLAN_CODE': plan,
        'ACCESS_ALLOWED': true,
        'MAX_USERS': 2,
        'MAX_DEVICES': 1,
        'ACCOUNTING_CORE': enabled,
        'WORKSHOP_REPAIRS': true,
      },
      validationRequiredAt: now.add(const Duration(days: 1)),
      validationGraceUntil: now.add(const Duration(days: 2)),
      operationalStatus: status);
}

class _Runtime extends LicenseRuntimeService {
  VerifiedLicense? value;
  @override
  Future<LicenseRuntimeDecision> refreshFromStoredLicense(
      {DateTime? now}) async {
    final current = value;
    return LicenseRuntimeDecision(
        mode: current == null
            ? 'ACTIVATION_REQUIRED'
            : SubscriptionAccessPolicy.mode(current, now ?? DateTime.now()),
        reason: 'unit boundary',
        license: current);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
      'commercial operation boundary denies missing/removed capability independently of plan label',
      () async {
    final runtime = _Runtime()..value = license();
    final service = SignedFeatureAuthorizationService(runtimeService: runtime);
    var writes = 0;
    Future<void> operation() async {
      writes++;
    }

    await service.execute('ACCOUNTING_CORE', operation);
    expect(writes, 1);
    runtime.value = license(enabled: false, revision: 5);
    await expectLater(service.execute('ACCOUNTING_CORE', operation),
        throwsA(isA<SignedFeatureDenied>()));
    expect(writes, 1);
    runtime.value = license(enabled: true, plan: 'FREE', revision: 6);
    await service.execute('ACCOUNTING_CORE', operation);
    expect(writes, 2,
        reason: 'only the signed capability, never a plan-name comparison');
    await expectLater(service.execute('UNKNOWN_FEATURE', operation),
        throwsA(isA<SignedFeatureDenied>()));
    for (final status in ['SUSPENDED', 'CANCELLED', 'EXPIRED', 'REVOKED']) {
      runtime.value = license(status: status);
      await expectLater(service.execute('ACCOUNTING_CORE', operation),
          throwsA(isA<SignedFeatureDenied>()));
    }
    runtime.value = null;
    await expectLater(service.execute('ACCOUNTING_CORE', operation),
        throwsA(isA<SignedFeatureDenied>()));
    expect(writes, 2);
  });

  test('permission feature mapping retains read, export and backup access', () {
    expect(CommercialFeatureCatalog.forPermission(PermissionKeys.invoicePost),
        'ACCOUNTING_CORE');
    expect(CommercialFeatureCatalog.forPermission(PermissionKeys.repairCreate),
        'WORKSHOP_REPAIRS');
    for (final permission in [
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
      PermissionKeys.backupCreate,
      PermissionKeys.backupExport,
      PermissionKeys.customerView
    ]) {
      expect(CommercialFeatureCatalog.forPermission(permission), isNull);
    }
  });

  Future<Database> database() async {
    final dir = await Directory.systemTemp.createTemp('phase6-feature-review-');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    return db;
  }

  Future<void> receipt(
      Database db, String org, Map<String, Object?> envelope) async {
    final now = DateTime.now().toUtc().toIso8601String();
    // Deliberately isolated projection fixture for SQL guards, not Gate E2E
    // signing evidence. E2E separately supplies actual Ed25519 envelopes.
    await db.insert('license_activation_state', {
      'singleton_id': 1,
      'organization_id': org,
      'device_id': 'device',
      'installation_id': 'install',
      'status': 'ACTIVE',
      'activation_id': 'activation',
      'license_id': 'license',
      'subscription_id': 'sub',
      'license_expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
      'entitlement_revision': 4,
      'signed_license_envelope_json': jsonEncode(envelope),
      'verification_keyset_json': '{}',
      'activated_at': now,
      'last_online_validation_at': now,
      'updated_at': now,
    });
  }

  test(
      'direct legacy SQL cannot mutate financial rows without signed feature; data remains readable',
      () async {
    final db = await database();
    final org = (await db.query('organization_identity'))
        .single['organization_id'] as String;
    await receipt(db, org, {
      'payload': {
        'entitlements': {'ACCOUNTING_CORE': true}
      }
    });
    final row = {
      'date': DateTime.now().toUtc().toIso8601String(),
      'accountName': 'fixture',
      'description': 'retained record'
    };
    await db.insert('journal_entries', row);
    final before = await db.query('journal_entries');
    for (final value in [false, null, 1, 'true']) {
      await db.update('license_activation_state', {
        'signed_license_envelope_json': jsonEncode({
          'payload': {
            'entitlements': {'ACCOUNTING_CORE': value}
          }
        })
      });
      await expectLater(
          db.insert('journal_entries', {...row, 'description': 'denied'}),
          throwsA(predicate(
              (e) => e.toString().contains('SIGNED_FEATURE_REQUIRED'))));
      await expectLater(
          db.update('journal_entries', {'description': 'denied'}),
          throwsA(predicate(
              (e) => e.toString().contains('SIGNED_FEATURE_REQUIRED'))));
      await expectLater(
          db.delete('journal_entries'),
          throwsA(predicate(
              (e) => e.toString().contains('SIGNED_FEATURE_REQUIRED'))));
      expect(await db.query('journal_entries'), before);
    }
    await db.update('backup_guardian_settings', {'weekly_enabled': 1});
    await db.update('license_activation_state', {
      'signed_license_envelope_json': jsonEncode({
        'payload': {
          'entitlements': {'ACCOUNTING_CORE': true}
        }
      })
    });
    await db.insert('journal_entries',
        {...row, 'description': 'restored after authority update'});
    expect((await db.query('journal_entries')).length, 2);
    // Reopening an existing workshop must not replay financial seed writes.
    await db.update('license_activation_state', {
      'signed_license_envelope_json': jsonEncode({
        'payload': {
          'entitlements': {'ACCOUNTING_CORE': false}
        }
      })
    });
    final existingPath = db.path;
    final installationId = const Uuid().v4(), deviceId = const Uuid().v4();
    final created = DateTime.now().toUtc().toIso8601String();
    await db.insert('installation_identity', {
      'singleton_id': 1,
      'organization_id': org,
      'installation_id': installationId,
      'device_id': deviceId,
      'public_key_b64url': 'projection-fixture',
      'public_key_sha256': 'a' * 64,
      'fingerprint_sha256': 'b' * 64,
      'platform': 'windows',
      'app_version': 'test',
      'binding_state': 'BOUND',
      'created_at': created,
      'updated_at': created,
    });
    await db.update('license_activation_state', {
      'installation_id': installationId,
      'device_id': deviceId,
    });
    await db.close();
    final reopened =
        await DatabaseMigration.initDatabase(pathOverride: existingPath);
    try {
      expect((await reopened.query('journal_entries')).length, 2);
      await expectLater(
          reopened.insert('journal_entries', row),
          throwsA(predicate(
              (e) => e.toString().contains('SIGNED_FEATURE_REQUIRED'))));
    } finally {
      await reopened.close();
    }
  });

  test(
      'a lower revision or older signed issue time cannot overwrite newer local receipt',
      () async {
    final db = await database();
    final org = (await db.query('organization_identity'))
        .single['organization_id'] as String;
    final issued = DateTime.now().toUtc();
    await receipt(db, org, {
      'payload': {
        'issued_at': issued.toIso8601String(),
        'entitlements': {'ACCOUNTING_CORE': false}
      }
    });
    final before = await db.query('license_activation_state');
    final device = DeviceIdentity(
        organizationId: org,
        installationId: 'install',
        deviceId: 'device',
        publicKeyBase64Url: 'x',
        publicKeySha256: 'a' * 64,
        fingerprintSha256: 'b' * 64,
        platform: 'windows',
        appVersion: 'test',
        identityGeneration: 1,
        bindingState: 'BOUND',
        createdAt: issued);
    for (final candidate in [
      license(org: org, revision: 3, issued: issued),
      license(
          org: org,
          revision: 4,
          issued: issued.subtract(const Duration(minutes: 1))),
    ]) {
      await expectLater(
          ActivationStateRepository(databaseProvider: () async => db)
              .commitVerifiedLicenseRefresh(
                  identity: device,
                  license: candidate,
                  lifecycleEventId: const Uuid().v4(),
                  envelope: {},
                  verificationKeyset: {},
                  serverTime: issued),
          throwsA(isA<StateError>()));
      expect(await db.query('license_activation_state'), before);
    }
  });
}
