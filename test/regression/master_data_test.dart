import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/suppliers/models/supplier.dart';
import 'package:yalla_accounts/features/suppliers/services/supplier_service.dart';
import 'package:yalla_accounts/features/vehicles/models/vehicle.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_intake_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair_intake_draft.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';
import 'package:yalla_accounts/features/account_statements/suppliers/services/supplier_statement_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Database db;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('master_regression_');
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
  });
  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();
    await temp.delete(recursive: true);
  });
  test('customer add edit lookup search duplicate warning and persistence',
      () async {
    final input = Client(
        name: 'Test Customer',
        type: 'أفراد',
        phone: '0599000111',
        email: 'test@example.invalid',
        address: 'Hebron',
        notes: 'special note');
    final id = await ClientService.insertClient(input);
    final saved = (await ClientService.getClientById(id))!;
    expect(saved.phone, input.phone);
    for (final q in [
      'Customer',
      '059900',
      'example.invalid',
      'Hebron',
      'special'
    ]) {
      expect((await ClientService.search(query: q)).map((c) => c.id),
          contains(id));
    }
    expect(await ClientService.search(query: "' OR 1=1 --"), isEmpty);
    expect(await ClientService.search(type: 'شركة تأمين'), isEmpty);
    await expectLater(
        ClientService.insertClient(input.copyWith(name: '  TEST   Customer  ')),
        throwsA(isA<DuplicateClientException>()));
    await expectLater(
        ClientService.insertClient(
            input.copyWith(name: ' TEST   Customer ', type: 'شركة تأمين')),
        throwsA(isA<DuplicateClientException>()));
    await ClientService.updateClient(
        saved.copyWith(name: 'Updated Customer', phone: '0599111222'));
    expect(
        (await PartyFinancialService.balances(executor: db))
            .firstWhere((p) => p.customerLegacyId == '$id')
            .displayName,
        'Updated Customer');
    await db.close();
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    expect((await ClientService.getClientById(id))!.phone, '0599111222');
    expect((await ClientService.getProfileSnapshot(id)).repairCount, 0);
    expect(await ClientService.deleteClient(id), 1);
    expect(await ClientService.getClientById(id), isNull);
    expect(
        (await PartyFinancialService.balances(executor: db))
            .where((p) => p.customerLegacyId == '$id'),
        isEmpty);
  });
  test('supplier CRUD blocks duplicate names on create and edit', () async {
    Supplier input(String name) => Supplier(
        id: '',
        pid: '',
        name: name,
        phone: '0599888',
        address: 'Industrial zone');
    final id = await SupplierService.insertSupplier(input('Parts Store'));
    await expectLater(SupplierService.insertSupplier(input('  PARTS   Store ')),
        throwsA(isA<DuplicateSupplierException>()));
    final second = await SupplierService.insertSupplier(input('Other Store'));
    final row = (await SupplierService.getAllSuppliers())
        .firstWhere((s) => s.id == second);
    await expectLater(
        SupplierService.updateSupplier(row.copyWith(name: 'Parts Store')),
        throwsA(isA<DuplicateSupplierException>()));
    final first =
        (await SupplierService.getAllSuppliers()).firstWhere((s) => s.id == id);
    await SupplierService.updateSupplier(
        first.copyWith(address: 'New address'));
    expect((await SupplierService.search(query: 'New address')).single.id, id);
    expect(await SupplierService.insertOrGetSupplierId('parts store'), id);
    await db.close();
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    expect((await SupplierService.search(query: 'New address')).single.id, id);
    expect(await SupplierService.deleteSupplier(first.pid), 1);
    expect(await SupplierService.search(query: 'Parts Store'), isEmpty);
    expect(
        (await PartyFinancialService.balances(executor: db))
            .where((p) => p.supplierLegacyId == id),
        isEmpty);
  });
  test('supplier purchases payments statement and deletion guard reconcile',
      () async {
    final session = await startAccountingSession(db, 'supplier-regression');
    try {
      final id = await SupplierService.insertSupplier(
          Supplier(id: '', pid: '', name: 'Financial supplier'));
      final invoice = await PurchaseInvoiceService.createInvoice(
          supplierId: int.parse(id),
          date: DateTime(2026, 9, 8),
          note: 'parts',
          items: [
            {'name': 'Brake pads', 'qty': 2, 'price': 500}
          ],
          method: 'credit');
      await VoucherPaymentService.insertAndPost(
          database: db,
          partyName: 'Financial supplier',
          voucher: VoucherPayment(
              id: 'supplier-regression-payment',
              voucherType: 'PAYMENT',
              partyType: 'SUPPLIER',
              partyId: id,
              amount: 300,
              currency: 'ILS',
              date: DateTime(2026, 9, 8),
              method: 'CASH',
              reference: invoice));
      final statement =
          await SupplierStatementService.load(supplierId: id, executor: db);
      expect(statement.closingBalance.abs(), 700);
      expect(statement.lines.any((l) => l.debit == 1000), isTrue);
      expect(statement.lines.any((l) => l.credit == 300), isTrue);
      await expectLater(SupplierService.deleteSupplier(id), throwsStateError);
    } finally {
      await session.endEphemeralPreviewSession();
    }
  });
  test(
      'vehicle plate normalization edit owner model/year and repair history persist',
      () async {
    final client = await ClientService.insertClient(
        Client(name: 'Vehicle owner', type: 'أفراد'));
    final id = await VehicleService.insertVehicle(Vehicle(
        number: '12-345-67',
        type: 'Toyota Corolla',
        model: '2020',
        clientId: client));
    await expectLater(
        VehicleService.insertVehicle(Vehicle(
            number: '١٢ ٣٤٥ ٦٧',
            type: 'Toyota',
            model: '2020',
            clientId: client)),
        throwsA(isA<DuplicateVehicleException>()));
    var vehicle = (await VehicleService.getAllVehicles()).single;
    await VehicleService.updateVehicle(
        vehicle.copyWith(type: 'Toyota Corolla sedan', model: '2021'));
    for (final date in [DateTime(2026, 8, 1), DateTime(2026, 9, 1)]) {
      await db.transaction((tx) => RepairIntakeService.saveOn(
          tx,
          RepairIntakeDraft(
              clientId: client,
              clientName: 'Vehicle owner',
              clientType: 'أفراد',
              vehicleNumber: '12-345-67',
              vehicleType: 'Toyota Corolla sedan',
              vehicleModel: '2021',
              receivedDate: date,
              odometer: 90000,
              fuelLevel: 50,
              previousDamage: 'None',
              photoPaths: [],
              customerSignaturePath: '')));
    }
    expect(await VehicleService.getHistory(id), hasLength(2));
    final repairs = RepairsService(db);
    expect(await repairs.list(search: 'Vehicle owner'), hasLength(2));
    expect(
        await repairs.list(from: '2026-09-01', to: '2026-09-01'), hasLength(1));
    expect(await repairs.list(search: "' OR 1=1 --"), isEmpty);

    expect(await VehicleService.getAllVehicles(), hasLength(1));
    expect((await ClientService.getProfileSnapshot(client)).repairCount, 2);
    await expectLater(ClientService.deleteClient(client), throwsStateError);
    await db.close();
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    vehicle = (await VehicleService.getAllVehicles()).single;
    expect(vehicle.clientId, client);
    expect(vehicle.model, '2021');
    expect(vehicle.repairCount, 2);
    expect(await VehicleService.getAllVehicles(query: 'Corolla'), hasLength(1));
    expect(await VehicleService.getAllVehicles(query: '١٢٣٤٥٦٧'), hasLength(1));
    expect(await VehicleService.getAllVehicles(query: 'missing'), isEmpty);
  });
}
