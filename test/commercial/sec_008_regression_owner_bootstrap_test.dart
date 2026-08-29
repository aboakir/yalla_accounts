import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/license_validation_tables.dart';
import 'package:yalla_accounts/features/auth/services/first_owner_bootstrap_service.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';

class _AlwaysUsableActivation extends ActivationStateRepository {
  _AlwaysUsableActivation({required super.databaseProvider});

  @override
  Future<bool> hasUsableActivationForCurrentInstallation() async => true;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('SEC.007 creates one owner and closes bootstrap', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec007_');
    final path = '${temp.path}${Platform.pathSeparator}bootstrap.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    Future<sq.Database> provider() async => db;

    try {
      expect(DatabaseConstants.dbVersion, greaterThanOrEqualTo(66));
      expect((await db.query('owner_bootstrap_state')).single['status'],
          'PENDING');
      final organizationId = (await db.query(
        'organization_identity',
        columns: ['organization_id'],
        where: 'singleton_id = 1',
      ))
          .single['organization_id']!
          .toString();
      final now = DateTime.now().toUtc();
      await db.insert('installation_identity', {
        'singleton_id': 1,
        'organization_id': organizationId,
        'installation_id': '11111111-1111-4111-8111-111111111111',
        'device_id': '22222222-2222-4222-8222-222222222222',
        'key_algorithm': 'ED25519',
        'public_key_b64url': 'test-public-key',
        'public_key_sha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'fingerprint_sha256':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'platform': 'windows',
        'platform_version': 'test',
        'app_version': '1.0.0+1',
        'identity_generation': 1,
        'binding_state': 'BOUND',
        'bound_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      final identity = (await db.query('installation_identity')).single;
      await db.insert('license_activation_state', {
        'singleton_id': 1,
        'organization_id': identity['organization_id'],
        'installation_id': identity['installation_id'],
        'device_id': identity['device_id'],
        'status': 'ACTIVE',
        'activation_id': '77777777-7777-4777-8777-777777777777',
        'license_id': '88888888-8888-4888-8888-888888888888',
        'subscription_id': '99999999-9999-4999-8999-999999999999',
        'license_expires_at':
            now.add(const Duration(days: 30)).toIso8601String(),
        'entitlement_revision': 1,
        'signed_license_envelope_json': '{"test":true}',
        'verification_keyset_json': '{"test":true}',
        'activated_at': now.toIso8601String(),
        'last_online_validation_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // SEC.012 regression fixture: a usable activation now also has a
      // signed validation window and a writable runtime projection.
      await LicenseValidationTables.projectSignedWindow(
        db,
        organizationId: organizationId,
        licenseId: '88888888-8888-4888-8888-888888888888',
        validationRequiredAt: now.add(const Duration(days: 30)),
        validationGraceUntil: now.add(const Duration(days: 37)),
        serverTime: now,
        markSuccess: true,
      );
      await db.update(
        LicenseRuntimeTables.table,
        <String, Object?>{
          'mode': LicenseRuntimeMode.writable,
          'reason': 'SEC.012 regression fixture: verified activation',
          'organization_id': organizationId,
          'subscription_id': '99999999-9999-4999-8999-999999999999',
          'license_id': '88888888-8888-4888-8888-888888888888',
          'effective_at': now.toIso8601String(),
          'license_expires_at':
              now.add(const Duration(days: 30)).toIso8601String(),
          'source': 'SIGNED_LICENSE',
          'last_verified_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        where: 'singleton_id = 1',
      );

      final service = FirstOwnerBootstrapService(
        databaseProvider: provider,
        activationStateRepository:
            _AlwaysUsableActivation(databaseProvider: provider),
      );
      final result = await service.createFirstOwner(
        const FirstOwnerBootstrapRequest(
          ownerName: 'owner007',
          password: 'OwnerPass007',
          workshopName: 'SEC007 Workshop',
          workshopAddress: 'Test Address',
          country: 'فلسطين',
          province: 'الضفة الغربية',
          city: 'Bethlehem',
          street: 'Test Street',
          phone: '0599000000',
        ),
      );

      final owner = (await db.query('users')).single;
      expect(owner['id'], result.ownerUserId);
      expect(owner['is_owner'], 1);
      expect(owner['role'], 'owner');
      expect(
          PasswordHasher.verify('OwnerPass007', owner['password']!.toString())
              .isValid,
          isTrue);
      expect(
          PasswordHasher.verify(
                  result.recoveryCode, owner['recovery_code_hash']!.toString())
              .isValid,
          isTrue);
      expect(owner.values.join('|'), isNot(contains(result.recoveryCode)));
      final state = (await db.query('owner_bootstrap_state')).single;
      expect(state['status'], 'COMPLETED');
      expect(state['owner_user_id'], result.ownerUserId);
      expect((await db.query('workshop_settings')).single['workshopName'],
          'SEC007 Workshop');

      await expectLater(
        service.createFirstOwner(
          const FirstOwnerBootstrapRequest(
            ownerName: 'second',
            password: 'SecondPass007',
            workshopName: 'Second',
            workshopAddress: '',
            country: 'فلسطين',
            province: '',
            city: '',
            street: '',
            phone: '0599111111',
          ),
        ),
        throwsA(isA<FirstOwnerBootstrapException>()),
      );
      expect((await db.query('users')).length, 1);
      expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first,
          'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
