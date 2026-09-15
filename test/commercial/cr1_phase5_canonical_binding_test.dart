import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/cloud_auth/supabase_identity_provider.dart';
import 'package:yalla_accounts/features/onboarding/approved_onboarding_activation_service.dart';
import 'package:yalla_accounts/features/onboarding/customer_onboarding_client.dart';
import 'package:yalla_accounts/features/onboarding/customer_onboarding_service.dart';

// Boundary stub only for local adversarial/rollback tests. The separate Phase 5
// E2E obtains all commercial records through real isolated Control HTTP flows.
class _Client extends CustomerOnboardingClient {
  _Client(this.userId, this.status)
      : super(
            sessionProvider: () async =>
                VerifiedOnboardingSession(userId, 'unit-only'));
  final String userId;
  CustomerOnboardingStatus status;
  bool offline = false;
  @override
  Future<CustomerOnboardingStatus> send(VerifiedOnboardingSession session,
      String operation, Map<String, Object?> body) async {
    if (offline) throw const CustomerOnboardingException('NETWORK');
    return status;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late Directory directory;
  late _Client client;
  late ApprovedOnboardingActivationService service;
  late String placeholder;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phase5-rebind-review-');
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${directory.path}/test.db');
    placeholder = (await db.query('organization_identity'))
        .single['organization_id'] as String;
    final now = DateTime.now().toUtc().toIso8601String();
    client = _Client(
        const Uuid().v4(),
        CustomerOnboardingStatus.parse({
          'contract_version': 2,
          'status': 'APPROVED',
          'request_id': const Uuid().v4(),
          'organization_id': const Uuid().v4(),
          'customer_id': const Uuid().v4(),
          'subscription_id': const Uuid().v4(),
          'license_id': const Uuid().v4(),
          'activation_id': const Uuid().v4(),
          'server_time': now,
          'submitted_at': now,
          'reviewed_at': now,
          'plan_code': 'PRO',
          'trial_days': 14,
          'license_status': 'PENDING_ACTIVATION',
          'activation_status': 'ISSUED',
        }));
    await CustomerOnboardingService(client: client, database: () async => db)
        .submit({'owner_name': 'Owner', 'organization_name': 'Workshop'});
    service = ApprovedOnboardingActivationService(
        client: client, database: () async => db);
  });
  tearDown(() async {
    client.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<String> snapshot() async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
    final values = <String, Object?>{};
    for (final table in tables) {
      final name = table['name'] as String;
      values[name] = await db.rawQuery('SELECT * FROM "$name"');
    }
    return jsonEncode(values);
  }

  test('unscoped legacy operational rows cannot be rebound, with zero mutation',
      () async {
    await db.execute(
        'CREATE TABLE legacy_financial_documents (id INTEGER PRIMARY KEY, amount REAL)');
    await db.insert('legacy_financial_documents', {'id': 1, 'amount': 123});
    final before = await snapshot();
    await expectLater(service.prepare(),
        throwsA(isA<ApprovedOnboardingActivationException>()));
    expect(await snapshot(), before);
  });

  test('fresh rebind is idempotent and retains immutable sync baseline',
      () async {
    final history = await db.query('sync_change_log');
    final entities = await db.query('sync_entity_registry');
    await service.prepare();
    final after = await snapshot();
    await service.prepare();
    expect(await snapshot(), after);
    expect(await db.query('sync_change_log'), history);
    final canonical = client.status.data['organization_id'];
    expect(canonical, isNot(placeholder));
    expect((await db.query('organization_identity')).single['organization_id'],
        canonical);
    expect(
        (await db.query('owner_bootstrap_state')).single['status'], 'PENDING');
    expect(await db.query('installation_identity'), isEmpty);
    expect(await db.query('users'), isEmpty);
    final rebound = await db.query('sync_entity_registry');
    expect(rebound.map((r) => r['entity_uuid']),
        entities.map((r) => r['entity_uuid']));
    expect(rebound.every((r) => r['organization_id'] == canonical), isTrue);
    await db.insert(
        'clients', {'name': 'future canonical record', 'type': 'individual'});
    final event = (await db.query('sync_change_log',
            where: 'entity_type = ?', whereArgs: ['client']))
        .single;
    expect(event['organization_id'], canonical);
  });

  test('late transaction failure preserves all rows and history', () async {
    await db.execute(
        "CREATE TRIGGER reject_rebind BEFORE DELETE ON organizations BEGIN SELECT RAISE(ABORT,'test rollback'); END");
    final before = await snapshot();
    await expectLater(service.prepare(), throwsA(anything));
    expect(await snapshot(), before);
  });

  test(
      'offline, mismatched request and other authenticated user cannot use cached approval',
      () async {
    final before = await snapshot();
    client.offline = true;
    await expectLater(
        service.prepare(), throwsA(isA<CustomerOnboardingException>()));
    client.offline = false;
    final other = _Client(const Uuid().v4(), client.status);
    addTearDown(other.close);
    await expectLater(
        ApprovedOnboardingActivationService(
            client: other, database: () async => db).prepare(),
        throwsA(isA<ApprovedOnboardingActivationException>()));
    client.status = CustomerOnboardingStatus.parse(
        {...client.status.data, 'request_id': const Uuid().v4()});
    await expectLater(service.prepare(),
        throwsA(isA<ApprovedOnboardingActivationException>()));
    expect(await snapshot(), before);
  });
}
