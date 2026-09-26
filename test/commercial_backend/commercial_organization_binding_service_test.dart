import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_organization_binding_service.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('canonical commercial organization replaces fresh local placeholder',
      () async {
    final dir = await Directory.systemTemp.createTemp('yallah_org_bind_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/binding.db',
    );
    addTearDown(() async {
      if (db.isOpen) await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final before = await db.query(
      'organization_identity',
      columns: const ['organization_id'],
      where: 'singleton_id = 1',
    );
    expect(before, hasLength(1));
    final oldId = before.single['organization_id']!.toString();
    final canonicalId = const Uuid().v4();
    expect(oldId, isNot(canonicalId));

    await CommercialOrganizationBindingService(
      databaseProvider: () async => db,
    ).reconcile(canonicalId);

    final identity = await db.query(
      'organization_identity',
      columns: const ['organization_id'],
      where: 'singleton_id = 1',
    );
    expect(identity.single['organization_id'], canonicalId);

    final bootstrap = await db.query(
      'owner_bootstrap_state',
      columns: const ['organization_id', 'status'],
      where: 'singleton_id = 1',
    );
    expect(bootstrap.single['organization_id'], canonicalId);
    expect(bootstrap.single['status'], 'PENDING');

    final organizations = await db.query(
      'organizations',
      columns: const ['id'],
    );
    expect(organizations, hasLength(1));
    expect(organizations.single['id'], canonicalId);

    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

    await CommercialOrganizationBindingService(
      databaseProvider: () async => db,
    ).reconcile(canonicalId);
  });
}
