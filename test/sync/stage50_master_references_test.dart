import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_document_references.dart';

void main() {
  late Database db;
  late Directory dir;
  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('stage50_masters_');
    db = await databaseFactoryFfi.openDatabase('${dir.path}/test.db');
    await db.execute(
        'CREATE TABLE organization_identity(singleton_id INTEGER,organization_id TEXT)');
    await db.insert(
        'organization_identity', {'singleton_id': 1, 'organization_id': 'org'});
    for (final table in [
      'clients',
      'suppliers',
      'employees',
      'parties',
      'accounts'
    ]) {
      await db.execute('CREATE TABLE $table(id INTEGER PRIMARY KEY,name TEXT)');
      await db.insert(table, {'id': 7, 'name': 'بيانات محفوظة'});
    }
    await db.execute(
        'CREATE TABLE vehicles(id INTEGER PRIMARY KEY,number TEXT,client_id INTEGER)');
    await db.insert('vehicles', {'id': 9, 'number': '12345', 'client_id': 7});
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test('master UUID upgrade preserves rows and identities across reopen',
      () async {
    final before = await db.query('clients');
    await SyncFoundationTables.ensure(db);
    final identities =
        await db.query(SyncFoundationTables.registry, orderBy: 'entity_type');
    expect(identities.length, 6);
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${dir.path}/test.db');
    await SyncFoundationTables.ensure(db);
    expect(await db.query('clients'), before);
    expect(
        await db.query(SyncFoundationTables.registry, orderBy: 'entity_type'),
        identities);
    await db.update('clients', {'name': 'تعديل'}, where: 'id=7');
    final changed = await db.query(SyncFoundationTables.changes,
        where: "entity_type='client' AND origin='local'");
    expect(changed.single['operation'], 'updated');
    expect(changed.single['before_json'], contains('بيانات محفوظة'));
    expect(changed.single['after_json'], contains('تعديل'));
  });
  test(
      'repair edges use UUIDs; ambiguous plate and foreign organization fail closed',
      () async {
    await SyncFoundationTables.ensure(db);
    Future<Map<String, Object?>> resolve(String org) =>
        SyncDocumentReferences.resolve(db,
            entityType: 'repair',
            organizationId: org,
            snapshot: {'client_id': 7, 'vehicleNumber': '12345'});
    final valid = await resolve('org');
    expect(valid['ready'], true);
    final refs = valid['references'] as Map;
    expect((refs['client_id'] as Map)['entity_uuid'], isNot('7'));
    expect((refs['vehicleNumber'] as Map)['entity_uuid'], isNot('9'));
    expect((await resolve('other'))['ready'], false);
    await db.insert('vehicles', {'id': 10, 'number': '12345', 'client_id': 7});
    expect((await resolve('org'))['unresolved'], contains('vehicleNumber'));
  });
  test('missing master cannot be silently matched by another field', () async {
    await SyncFoundationTables.ensure(db);
    final result = await SyncDocumentReferences.resolve(db,
        entityType: 'invoice',
        organizationId: 'org',
        snapshot: {'client_id': 99, 'name': 'بيانات محفوظة'});
    expect(result['ready'], false);
    expect(result['unresolved'], ['client_id']);
  });
}
