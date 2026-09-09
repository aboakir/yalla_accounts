import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair_intake_draft.dart';
import 'package:yalla_accounts/features/repairs/services/repair_intake_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';
import '../support/accounting_session.dart';

Future<Map<String, Object?>> totals(Database db) async {
  final result = <String, Object?>{};
  for (final t in [
    'clients',
    'repairs',
    'payments',
    'vouchers',
    'gl_entries',
    'gl_lines'
  ]) {
    result[t] =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t'));
  }
  result['lines'] = await db.rawQuery(
      'SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM gl_lines');
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  test('real v55 upgrade preserves history and is repeatable', () async {
    final source = Platform.environment['YALLA_LEGACY_TEST_DB'];
    if (source == null) return;
    final dir = await Directory.systemTemp.createTemp('migration55_');
    final path = '${dir.path}/old.db';
    await File(source).copy(path);
    var db = await databaseFactoryFfi.openDatabase(path);
    try {
      final before = await totals(db);
      expect(await db.getVersion(), 55);
      await db.close();
      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      expect(await totals(db), before);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await totals(db), before);
      expect(await db.query('schema_migrations'), hasLength(1));
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  },
      skip: Platform.environment['YALLA_LEGACY_TEST_DB'] == null
          ? 'Set YALLA_LEGACY_TEST_DB to an isolated v55 snapshot'
          : false);

  test('v69 migration is atomic, preserves data, refuses downgrade/reset',
      () async {
    final dir = await Directory.systemTemp.createTemp('migration69_');
    final path = '${dir.path}/db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      await db.insert(
          'clients', {'name': 'Preserved customer', 'type': 'individual'});
      await db.execute('DELETE FROM schema_migrations');
      await db.execute(
          "CREATE TRIGGER reject_migration BEFORE INSERT ON schema_migrations BEGIN SELECT RAISE(ABORT,'injected migration failure'); END");
      await db.setVersion(69);
      await db.close();
      await expectLater(DatabaseMigration.initDatabase(pathOverride: path),
          throwsA(anything));
      db = await databaseFactoryFfi.openDatabase(path);
      expect(await db.getVersion(), 69);
      expect(await db.query('schema_migrations'), isEmpty);
      await db.execute('DROP TRIGGER reject_migration');
      await db.close();
      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect((await db.query('clients')).single['name'], 'Preserved customer');
      expect(await db.getVersion(), DatabaseConstants.dbVersion);
      await db.setVersion(DatabaseConstants.dbVersion + 1);
      await db.close();
      await expectLater(DatabaseMigration.initDatabase(pathOverride: path),
          throwsA(anything));
      db = await databaseFactoryFfi.openDatabase(path);
      expect(await db.getVersion(), DatabaseConstants.dbVersion + 1);
      expect((await db.query('clients')).single['name'], 'Preserved customer');
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test(
      'repair, receipt, payment and customer update roll back on mid-write failure',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('atomic_services_');
    final path = '${dir.path}/db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'reliability-owner');
    await db.update('owner_bootstrap_state', {
      'status': 'COMPLETED',
      'owner_user_id': 'reliability-owner',
      'completed_at': DateTime.now().toIso8601String()
    });
    try {
      await db.execute(
          "CREATE TRIGGER fail_account BEFORE INSERT ON accounts WHEN NEW.code LIKE '1200.C%' BEGIN SELECT RAISE(ABORT,'injected account failure'); END");
      await expectLater(
          ClientService.insertClient(
              Client(name: 'Must roll back', type: 'individual')),
          throwsA(anything));
      expect(await db.query('clients'), isEmpty);
      await db.execute('DROP TRIGGER fail_account');
      final id = await ClientService.insertClient(
          Client(name: 'Original', type: 'individual'));
      Future<void> receive() => PaymentService.insertCanonicalReceipt(
              database: db,
              operationId: 'one-receipt',
              clientId: id,
              customerName: 'Original',
              method: 'cash',
              date: DateTime(2026, 9, 9),
              allocations: [],
              unallocatedAmount: 100)
          .then((_) {});
      Future<void> spend() => VoucherPaymentService.insertAndPost(
              database: db,
              partyName: 'Expense',
              voucher: VoucherPayment(
                  id: 'one-payment',
                  voucherType: 'PAYMENT',
                  partyType: 'EXPENSE',
                  amount: 20,
                  currency: 'ILS',
                  date: DateTime(2026, 9, 9),
                  method: 'CASH'))
          .then((_) {});
      final draft = RepairIntakeDraft(
          clientName: 'New intake client',
          clientType: 'individual',
          vehicleNumber: 'TEST-123',
          vehicleType: 'Car',
          vehicleModel: '2020',
          receivedDate: DateTime(2026, 9, 9),
          odometer: 100,
          fuelLevel: 50,
          previousDamage: '',
          photoPaths: [],
          customerSignaturePath: '');
      final before = await totals(db);
      await db.execute(
          "CREATE TRIGGER fail_repair AFTER INSERT ON repairs BEGIN SELECT RAISE(ABORT,'injected repair failure'); END");
      await expectLater(RepairIntakeService.save(draft), throwsA(anything));
      expect(await totals(db), before);
      expect(await db.query('vehicles'), isEmpty);
      await db.execute('DROP TRIGGER fail_repair');
      await db.execute(
          "CREATE TRIGGER fail_ledger BEFORE INSERT ON gl_lines WHEN NEW.credit > 0 BEGIN SELECT RAISE(ABORT,'injected ledger failure'); END");
      await expectLater(receive(), throwsA(anything));
      expect(await totals(db), before);
      await expectLater(spend(), throwsA(anything));
      expect(await totals(db), before);
      await db.execute('DROP TRIGGER fail_ledger');
      await db.execute(
          "CREATE TRIGGER fail_client AFTER UPDATE ON clients BEGIN SELECT RAISE(ABORT,'injected client failure'); END");
      await expectLater(
          ClientService.updateClient(
              Client(id: id, name: 'Changed', type: 'individual')),
          throwsA(anything));
      expect(
          (await db.query('clients', where: 'id=?', whereArgs: [id]))
              .single['name'],
          'Original');
      await db.execute('DROP TRIGGER fail_client');
      await RepairIntakeService.save(draft);
      await receive();
      await spend();
      final committed = await totals(db);
      await session.logout();
      await db.close();
      db = await DatabaseMigration.initDatabase(pathOverride: path);
      DatabaseMigration.useDatabaseForTesting(db);
      expect(await totals(db), committed);
      expect(await db.rawQuery('PRAGMA integrity_check'), [
        {'integrity_check': 'ok'}
      ]);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
