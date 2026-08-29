import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/identity/organization_identity_service.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('SEC.001 fresh database creates one stable organization UUID', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec001_fresh_');
    final path = '${temp.path}${Platform.pathSeparator}fresh.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      final version = sq.Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      expect(version, DatabaseConstants.dbVersion);

      final identity = await OrganizationIdentityService(
        databaseProvider: () async => db,
      ).current();

      expect(
        identity.organizationId,
        matches(
          RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
            r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
          ),
        ),
      );
      expect(identity.isActive, isTrue);

      final orgCount = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM organizations'),
          ) ??
          0;
      final identityCount = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM organization_identity'),
          ) ??
          0;
      expect(orgCount, 1);
      expect(identityCount, 1);

      final same = await OrganizationIdentityService(
        databaseProvider: () async => db,
      ).requireOrganizationId();
      expect(same, identity.organizationId);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('SEC.001 local rows default to the current organization', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec001_scope_');
    final path = '${temp.path}${Platform.pathSeparator}scope.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);

    try {
      final organizationId = await OrganizationIdentityService(
        databaseProvider: () async => db,
      ).requireOrganizationId();

      await db.insert('workshop_settings', {
        'id': 1,
        'workshopName': 'SEC.001 Test Workshop',
      });
      final workshop = (await db.query(
        'workshop_settings',
        columns: ['organization_id'],
        where: 'id = 1',
      ))
          .single;
      expect(workshop['organization_id'], organizationId);

      await db.insert('users', {
        'id': 'legacy-compatible-user-id',
        'name': 'sec001-user',
        'email': '',
        'password': 'test-only-hash',
        'role': 'owner',
        'status': 'active',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_owner': 1,
      });
      final user = (await db.query(
        'users',
        where: 'id = ?',
        whereArgs: ['legacy-compatible-user-id'],
      ))
          .single;
      expect(user['organization_id'], organizationId);

      final appUser = AppUser.fromMap(user);
      expect(appUser.organizationId, organizationId);

      await expectLater(
        db.insert('users', {
          'id': 'foreign-org-user',
          'name': 'foreign-org-user',
          'email': '',
          'password': 'test-only-hash',
          'role': 'user',
          'status': 'active',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'organization_id': '11111111-1111-4111-8111-111111111111',
        }),
        throwsA(isA<sq.DatabaseException>()),
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('SEC.001 reopen does not rotate organization identity', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_sec001_reopen_');
    final path = '${temp.path}${Platform.pathSeparator}reopen.db';

    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    final first = await OrganizationIdentityService(
      databaseProvider: () async => db,
    ).requireOrganizationId();
    await db.close();

    db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      final second = await OrganizationIdentityService(
        databaseProvider: () async => db,
      ).requireOrganizationId();
      expect(second, first);

      final count = sq.Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM organizations'),
          ) ??
          0;
      expect(count, 1);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
