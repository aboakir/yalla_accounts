import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';

class _FixedActivationState extends ActivationStateRepository {
  _FixedActivationState(this.license, {required super.databaseProvider});

  final VerifiedLicense? license;

  @override
  Future<VerifiedLicense?> loadAuthenticLicenseForCurrentInstallation({
    bool allowExpired = false,
  }) async =>
      license;
}

VerifiedLicense _license({
  required String organizationId,
  String subscriptionId = '22222222-2222-4222-8222-222222222222',
  String operationalStatus = 'ACTIVE',
  DateTime? expiresAt,
}) {
  final now = DateTime.now().toUtc();
  return VerifiedLicense(
    licenseId: '11111111-1111-4111-8111-111111111111',
    organizationId: organizationId,
    subscriptionId: subscriptionId,
    deviceId: '33333333-3333-4333-8333-333333333333',
    installationId: '44444444-4444-4444-8444-444444444444',
    issuedAt: now.subtract(const Duration(minutes: 5)),
    notBefore: now.subtract(const Duration(minutes: 5)),
    expiresAt: expiresAt ?? now.add(const Duration(days: 30)),
    entitlementRevision: 9,
    entitlements: const <String, Object?>{
      'ACCOUNTING_CORE': true,
      'MAX_USERS': 5,
      'MAX_DEVICES': 2,
    },
    validationRequiredAt: now.add(const Duration(days: 7)),
    validationGraceUntil: now.add(const Duration(days: 14)),
    operationalStatus: operationalStatus,
  );
}

Future<AppUser> _seedCompletedOwner(sq.Database db) async {
  final organizationId = (await db.query(
    'organization_identity',
    columns: ['organization_id'],
    where: 'singleton_id = 1',
  ))
      .single['organization_id']!
      .toString();
  const ownerId = '55555555-5555-4555-8555-555555555555';
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('users', <String, Object?>{
    'id': ownerId,
    'name': 'stage02-owner',
    'email': 'owner@stage02.test',
    'password': 'test-hash',
    'role': 'owner',
    'status': 'active',
    'created_at': now,
    'organization_id': organizationId,
    'is_owner': 1,
    'must_change_password': 0,
  });
  await db.update(
    'owner_bootstrap_state',
    <String, Object?>{
      'status': 'COMPLETED',
      'owner_user_id': ownerId,
      'activation_id': '66666666-6666-4666-8666-666666666666',
      'completed_at': now,
      'updated_at': now,
    },
    where: 'singleton_id = 1',
  );
  return AppUser.fromMap(
    (await db.query('users', where: 'id = ?', whereArgs: [ownerId])).single,
  );
}

Future<void> _withDb(
  Future<void> Function(
    sq.Database db,
    AppUser owner,
    String organizationId,
  ) body,
) async {
  final temp = await Directory.systemTemp.createTemp('yalla_stage02_');
  final path = '${temp.path}${Platform.pathSeparator}stage02.db';
  final db = await DatabaseMigration.initDatabase(pathOverride: path);
  try {
    final owner = await _seedCompletedOwner(db);
    await body(db, owner, owner.organizationId!);
  } finally {
    await db.close();
    await temp.delete(recursive: true);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('Stage 02 accepts only the canonical commercial identity chain',
      () async {
    await _withDb((db, owner, organizationId) async {
      Future<sq.Database> provider() async => db;
      final gate = CommercialAccessGateService(
        databaseProvider: provider,
        activationStateRepository: _FixedActivationState(
          _license(organizationId: organizationId),
          databaseProvider: provider,
        ),
      );

      final decision = await gate.evaluate(owner);
      expect(decision.allowed, isTrue);
      expect(decision.readOnly, isFalse);
      expect(decision.requiresActivation, isFalse);
      expect(decision.code, 'BOUND_WRITABLE');
      expect(decision.license?.organizationId, organizationId);
      expect(decision.license?.subscriptionId, isNotEmpty);
      expect(decision.license?.deviceId, isNotEmpty);
      expect(decision.license?.installationId, isNotEmpty);
    });
  });

  test('Stage 02 rejects local paid/trial fields as an access bypass',
      () async {
    await _withDb((db, owner, _) async {
      Future<sq.Database> provider() async => db;
      final forgedLegacyState = owner.copyWith(
        freeTrialEnd: DateTime.now().add(const Duration(days: 365)),
        subscriptionEndDate: DateTime.now().add(const Duration(days: 365)),
        paymentStatus: 'مدفوع',
      );
      final gate = CommercialAccessGateService(
        databaseProvider: provider,
        activationStateRepository:
            _FixedActivationState(null, databaseProvider: provider),
      );

      final decision = await gate.evaluate(forgedLegacyState);
      expect(decision.allowed, isFalse);
      expect(decision.requiresActivation, isTrue);
      expect(decision.code, 'ACTIVATION_REQUIRED');
    });
  });

  test('Stage 02 rejects missing subscription and organization mismatch',
      () async {
    await _withDb((db, owner, organizationId) async {
      Future<sq.Database> provider() async => db;
      final noSubscription = CommercialAccessGateService(
        databaseProvider: provider,
        activationStateRepository: _FixedActivationState(
          _license(organizationId: organizationId, subscriptionId: ''),
          databaseProvider: provider,
        ),
      );
      expect(
        (await noSubscription.evaluate(owner)).code,
        'SUBSCRIPTION_MISSING',
      );

      final wrongOrganization = CommercialAccessGateService(
        databaseProvider: provider,
        activationStateRepository: _FixedActivationState(
          _license(
            organizationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          ),
          databaseProvider: provider,
        ),
      );
      final mismatch = await wrongOrganization.evaluate(owner);
      expect(mismatch.allowed, isFalse);
      expect(mismatch.code, 'LICENSE_ORGANIZATION_MISMATCH');
    });
  });

  test('Stage 02 preserves SEC.011 read-only lifecycle behavior', () async {
    await _withDb((db, owner, organizationId) async {
      Future<sq.Database> provider() async => db;
      final gate = CommercialAccessGateService(
        databaseProvider: provider,
        activationStateRepository: _FixedActivationState(
          _license(
            organizationId: organizationId,
            operationalStatus: 'SUSPENDED',
          ),
          databaseProvider: provider,
        ),
      );

      final decision = await gate.evaluate(owner);
      expect(decision.allowed, isTrue);
      expect(decision.readOnly, isTrue);
      expect(decision.code, 'BOUND_READ_ONLY');
    });
  });

  test('Stage 02 login and route gate both enforce commercial access',
      () async {
    final login = await File('lib/features/auth/screens/login_screen.dart')
        .readAsString();
    final route = await File(
      'lib/features/auth/widgets/authenticated_route_gate.dart',
    ).readAsString();
    expect(login, contains('commercialAccessGateServiceProvider'));
    expect(login, contains('if (!commercialAccess.allowed)'));
    expect(route, contains('commercialAccessGateServiceProvider'));
    expect(
      route,
      contains('if (commercial == null || !commercial.allowed)'),
    );
  });
}
