import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/core/services/db/tables/owner_bootstrap_tables.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/subscription_access_policy.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/subscription/screens/current_subscription_screen.dart';

VerifiedLicense license(String status, DateTime now,
        {DateTime? expiry, DateTime? grace, String organizationId = 'org'}) =>
    VerifiedLicense(
        licenseId: 'license',
        organizationId: organizationId,
        subscriptionId: 'sub',
        deviceId: 'device',
        installationId: 'install',
        issuedAt: now.subtract(const Duration(days: 1)),
        notBefore: now.subtract(const Duration(days: 1)),
        expiresAt: expiry ?? now.add(const Duration(days: 30)),
        entitlementRevision: 1,
        entitlements: const {
          'ACCOUNTING_CORE': true,
          'MAX_USERS': 5,
          'MAX_DEVICES': 2
        },
        validationRequiredAt: now.subtract(const Duration(days: 1)),
        validationGraceUntil: grace ?? now.add(const Duration(days: 7)),
        operationalStatus: status);

class Repository extends ActivationStateRepository {
  VerifiedLicense? value;
  bool persisted = true;
  @override
  Future<bool> hasPersistedActivationState() async => persisted;
  @override
  Future<VerifiedLicense?> loadAuthenticLicenseForCurrentInstallation(
          {bool allowExpired = false}) async =>
      value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final now = DateTime.now().toUtc();
  const writable = {'ACTIVE', 'TRIAL', 'GRACE', 'EXCEPTION'};
  for (final status in SubscriptionAccessPolicy.statuses) {
    test(
        '$status projects identical local/server policy and enforces SQL writes',
        () async {
      final dir = await Directory.systemTemp.createTemp('stage46_');
      final db = await DatabaseMigration.initDatabase(
          pathOverride: '${dir.path}/test.db');
      final orgId = (await db.query('organizations')).first['id'].toString();
      await db.insert('users', {
        'id': 'owner',
        'name': 'owner',
        'password': 'fixture',
        'role': 'owner',
        'is_owner': 1,
        'status': 'active',
        'created_at': now.toIso8601String(),
        'organization_id': orgId
      });
      await OwnerBootstrapTables.ensure(db);
      final user = AppUser.fromMap((await db.query('users')).single);
      final repo = Repository()
        ..value = license(status, now, organizationId: orgId);
      final access = await CommercialAccessGateService(
              databaseProvider: () async => db, activationStateRepository: repo)
          .evaluate(user);
      expect(access.allowed, isTrue);
      expect(access.readOnly, !writable.contains(status));
      final service = LicenseRuntimeService(
          databaseProvider: () async => db, activationStateRepository: repo);
      try {
        final decision = await service.refreshFromStoredLicense(now: now);
        expect(decision.isWritable, writable.contains(status));
        await service.projectServerLifecycleDecision(
            license: repo.value!, serverTime: now);
        expect((await service.current()).mode, decision.mode);
        if (writable.contains(status)) {
          await service.requireOperationalWrite();
          await db.insert('clients', {'name': 'allowed', 'type': 'individual'});
        } else {
          await expectLater(service.requireOperationalWrite(),
              throwsA(isA<ReadOnlyOperationException>()));
          await expectLater(
              db.insert('clients', {'name': 'blocked', 'type': 'individual'}),
              throwsA(anything));
          await db.query('clients');
          await db.update('backup_guardian_settings', {'weekly_enabled': 1});
          await db.insert('app_audit_events', {
            'created_at': now.toIso8601String(),
            'action': 'BACKUP_CREATED',
            'entity_type': 'BACKUP'
          });
        }
      } finally {
        await db.close();
      }
    });
  }
  test('clock expiry and offline grace override signed writable states', () {
    for (final status in writable) {
      expect(
          SubscriptionAccessPolicy.mode(license(status, now, expiry: now), now),
          'READ_ONLY_EXPIRED');
      expect(
          SubscriptionAccessPolicy.mode(license(status, now, grace: now), now),
          'READ_ONLY_VALIDATION_REQUIRED');
    }
    expect(SubscriptionAccessPolicy.mode(license('unknown', now), now),
        'READ_ONLY_REVOKED');
    expect(SubscriptionAccessPolicy.mode(license(' trial ', now), now),
        'WRITABLE');
  });
  test('local clock rollback behind trusted server time fails closed',
      () async {
    final dir = await Directory.systemTemp.createTemp('stage46_clock_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    final orgId = (await db.query('organizations')).first['id'].toString();
    final trusted = DateTime.now().toUtc();
    final repo = Repository()
      ..value = license('ACTIVE', trusted, organizationId: orgId);
    final service = LicenseRuntimeService(
        databaseProvider: () async => db, activationStateRepository: repo);
    try {
      await service.projectServerLifecycleDecision(
          license: repo.value!, serverTime: trusted);
      final rolledBack = await service.refreshFromStoredLicense(
          now: trusted.subtract(const Duration(hours: 1)));
      expect(rolledBack.mode, 'READ_ONLY_VALIDATION_REQUIRED');
      expect(rolledBack.reason, contains('clock'));
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('DB trigger blocks writes when trusted licensing time is in the future',
      () async {
    final dir = await Directory.systemTemp.createTemp('stage46_clock_db_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    final orgId = (await db.query('organizations')).first['id'].toString();
    final trustedFuture = DateTime.now().toUtc().add(const Duration(hours: 1));
    final repo = Repository()
      ..value = license('ACTIVE', trustedFuture, organizationId: orgId);
    final service = LicenseRuntimeService(
        databaseProvider: () async => db, activationStateRepository: repo);
    try {
      await service.projectServerLifecycleDecision(
          license: repo.value!, serverTime: trustedFuture);
      await expectLater(
          db.insert('clients', {'name': 'blocked-clock', 'type': 'individual'}),
          throwsA(anything));
      expect(await db.query('clients'), isEmpty);
      final correctedServerTime = DateTime.now().toUtc();
      await service.projectServerLifecycleDecision(
          license: repo.value!, serverTime: correctedServerTime);
      await db.insert('clients',
          {'name': 'allowed-after-validation', 'type': 'individual'});
      expect((await db.query('clients')).length, 1);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('missing or invalid signed license cannot authorize writes', () async {
    final dir = await Directory.systemTemp.createTemp('stage46_invalid_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    final repo = Repository()..persisted = false;
    final service = LicenseRuntimeService(
        databaseProvider: () async => db, activationStateRepository: repo);
    try {
      await expectLater(service.requireOperationalWrite(),
          throwsA(isA<ReadOnlyOperationException>()));
      repo.persisted = true;
      await expectLater(service.requireOperationalWrite(),
          throwsA(isA<ReadOnlyOperationException>()));
    } finally {
      await db.close();
    }
  });
  for (final size in [
    const Size(430, 932),
    const Size(390, 844),
    const Size(844, 390)
  ]) {
    testWidgets('Arabic status expiry and readonly message fit $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: CurrentSubscriptionScreen(
              load: () async => LicenseRuntimeDecision(
                  mode: 'READ_ONLY_SUSPENDED',
                  reason: '',
                  license: license('FROZEN', now)))));
      await tester.pumpAndSettle();
      expect(find.text('حالة الاشتراك: مجمّد'), findsOneWidget);
      expect(find.text('القراءة فقط'), findsOneWidget);
      expect(find.textContaining('تاريخ الانتهاء:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
