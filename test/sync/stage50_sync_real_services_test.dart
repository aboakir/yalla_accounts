import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';
import 'package:yalla_accounts/features/employees/models/advance.dart';
import 'package:yalla_accounts/features/employees/services/advance_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/edit_repair_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_workflow_service.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/device_identity/device_fingerprint_service.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_secret_store.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/supplier_payment_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair_intake_draft.dart';
import 'package:yalla_accounts/features/repairs/services/repair_intake_service.dart';
import '../support/accounting_session.dart';

class _MemorySecrets implements DeviceIdentitySecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Fingerprint implements DeviceFingerprintProvider {
  @override
  Future<DeviceFingerprintSnapshot> collect() async =>
      const DeviceFingerprintSnapshot(
          sha256Hex:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          platform: 'windows',
          platformVersion: 'isolated-test',
          appVersion: '1.0.0+1');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real repair, receipt, GL and supplier voucher paths capture verified user and device without duplicate posting',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('stage50_real_services_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'stage50-accountant');
    try {
      await SyncFoundationTables.ensure(db);
      final device = await DeviceIdentityService(
              databaseProvider: () async => db,
              secretStore: _MemorySecrets(),
              fingerprintProvider: _Fingerprint())
          .ensureCurrent();
      final repairId = await RepairIntakeService.save(RepairIntakeDraft(
          clientName: 'Stage50 client',
          clientType: 'individual',
          vehicleNumber: 'TEST-50',
          vehicleType: 'test',
          vehicleModel: '2026',
          receivedDate: DateTime.utc(2026, 9, 9),
          odometer: 1,
          fuelLevel: 50,
          previousDamage: '',
          photoPaths: const [],
          customerSignaturePath: '',
          notes: ''));
      final repair =
          (await db.query('repairs', where: 'id=?', whereArgs: [repairId]))
              .single;
      final client = repair['client_id'] as int;
      Future<CanonicalReceiptResult> receive() =>
          PaymentService.insertCanonicalReceipt(
              database: db,
              operationId: 'stage50-receipt',
              clientId: client,
              customerName: 'Stage50 client',
              method: 'cash',
              date: DateTime.utc(2026, 9, 9),
              allocations: const [],
              unallocatedAmount: 120);
      final receipt = await receive();
      final entryCount = (await db.query('gl_entries')).length;
      final changeCount = (await db.query(SyncFoundationTables.changes)).length;
      expect((await receive()).receiptNumber, receipt.receiptNumber);
      expect((await db.query('gl_entries')).length, entryCount);
      expect(
          (await db.query(SyncFoundationTables.changes)).length, changeCount);
      final supplier = await SyncFoundationService.transaction(
          db, (txn) => txn.insert('suppliers', {'name': 'Stage50 supplier'}));
      final glId = await SupplierPaymentService.insertAndPost(
          database: db,
          operationId: 'stage50-supplier',
          supplierId: supplier,
          amount: 10,
          date: DateTime.utc(2026, 9, 9),
          method: 'CASH');
      expect(
          await SupplierPaymentService.insertAndPost(
              database: db,
              operationId: 'stage50-supplier',
              supplierId: supplier,
              amount: 10,
              date: DateTime.utc(2026, 9, 9),
              method: 'CASH'),
          glId);
      // These active save paths previously used raw database transactions or
      // follow-up writes and therefore lost the authenticated actor.
      await InvoiceService.instance.createOrGetByRepair(
          repairId: repairId,
          date: DateTime.utc(2026, 9, 9),
          total: 0,
          clientId: client);
      await PurchaseInvoiceService.createInvoice(
          id: 'stage50-purchase',
          supplierId: supplier,
          date: DateTime.utc(2026, 9, 9),
          note: 'attribution regression',
          method: 'cash',
          items: [
            {'item': 'test part', 'qty': 1, 'price': 25}
          ]);
      await EditRepairService.editRepairWithAccounting(
          database: db,
          repairId: repairId,
          updatedRepair: Repair.fromMap(repair),
          newParts: [],
          newWorks: [],
          notes: 'edited through real service',
          editedBy: 'stage50-accountant');
      await RepairWorkflowService.prepareEstimate(
          repairId: repairId,
          damageAssessment: 'attributed assessment',
          validUntil: DateTime(2026, 10, 1));
      final employeeInfo = await db.rawQuery('PRAGMA table_info(employees)');
      final employee = <String, Object?>{
        for (final column in employeeInfo)
          if (column['notnull'] == 1 && column['dflt_value'] == null)
            column['name'] as String:
                '${column['type']}'.toUpperCase().contains('TEXT') ? '' : 0,
        'id': 'stage50-employee',
        'full_name': 'Stage50 employee',
        'employee_code': 'STAGE50',
        'status': 'active',
        'payment_method': 'cash',
        'hire_date': '2026-01-01',
        'created_at': '2026-09-09',
      };
      await SyncFoundationService.transaction(
          db, (txn) => txn.insert('employees', employee));
      await AdvanceDatabaseService.insertAdvance(
          advance: Advance(
              id: 'stage50-advance',
              employeeId: 'stage50-employee',
              amount: 10,
              type: 'advance',
              date: DateTime.utc(2026, 9, 9),
              method: 'cash'));
      final payrollId = await PayrollDatabaseService.accrue(
          employeeId: 'stage50-employee',
          periodStart: DateTime(2026, 9, 1),
          periodEnd: DateTime(2026, 9, 30),
          accrualDate: DateTime(2026, 9, 30),
          gross: 1000,
          advanceApplied: 0,
          method: 'cash');
      await PayrollDatabaseService.syncPaymentState(payrollId);
      final nestedResult = await SyncFoundationService.transaction(
          db,
          (txn) => SyncFoundationService.writeOn(txn, (sameTxn) async {
                expect(identical(txn, sameTxn), isTrue);
                return 73;
              }));
      expect(nestedResult, 73);
      final history =
          await db.query(SyncFoundationTables.changes, where: "origin='local'");
      expect(
          history.map((r) => r['entity_type']),
          containsAll([
            'repair',
            'receipt',
            'payment',
            'gl_entry',
            'gl_line',
            'voucher'
          ]));
      for (final row in history) {
        expect(row['user_id'], 'stage50-accountant',
            reason:
                '${row['entity_type']}:${row['entity_id']} ${row['operation']}');
        expect(row['device_id'], device.deviceId);
        expect(row['organization_id'], device.organizationId);
        expect(row['attribution_state'], 'attributed');
      }
      expect(await db.query(SyncFoundationTables.context), isEmpty);
      final invoice = await SyncFoundationService.identityFor(db,
          entityType: 'repair', localId: repairId);
      expect(invoice, isNotNull);
      await expectLater(
          SyncFoundationService.transaction(db, (txn) async {
            await txn.update('repairs', {'notes': 'must roll back'},
                where: 'id=?', whereArgs: [repairId]);
            throw StateError('failure inside attributed action');
          }),
          throwsStateError);
      expect(await db.query(SyncFoundationTables.context), isEmpty);
      await session.endEphemeralPreviewSession();
      await SyncFoundationService.transaction(
          db,
          (txn) => txn.update('repairs', {'notes': 'signed out'},
              where: 'id=?', whereArgs: [repairId]));
      final last = (await db.query(SyncFoundationTables.changes,
              where: 'entity_type=? AND entity_id=?',
              whereArgs: ['repair', repairId],
              orderBy: 'sequence DESC',
              limit: 1))
          .single;
      expect(last['user_id'], isNull);
      expect(last['attribution_state'], 'unavailable');
      expect(SyncFoundationService.remoteFinancialSyncEnabled, isFalse);
      await SyncFoundationTables.validate(db);
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
