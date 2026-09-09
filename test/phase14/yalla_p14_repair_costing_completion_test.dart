import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db
        .execute('CREATE TABLE repairs(id TEXT PRIMARY KEY, fileValue REAL)');
    await db.execute('''
      CREATE TABLE payments(
        id TEXT PRIMARY KEY,
        repair_id TEXT,
        relatedRepairId TEXT,
        amount REAL,
        isIncome INTEGER DEFAULT 1
      )
    ''');
    await db
        .execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY, code TEXT)');
    await db.execute(
        'CREATE TABLE gl_entries(id INTEGER PRIMARY KEY, source TEXT, reversal_of INTEGER)');
    await db.execute('''
      CREATE TABLE gl_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER,
        account_id INTEGER,
        debit REAL,
        credit REAL,
        repair_id TEXT,
        party_type TEXT,
        party_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE purchase_invoices(
        id TEXT PRIMARY KEY,
        date TEXT,
        purchase_type TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE purchase_invoice_lines(
        id TEXT PRIMARY KEY,
        invoice_id TEXT,
        item TEXT,
        item_name TEXT,
        qty REAL,
        unit_price REAL,
        price REAL,
        total REAL,
        category TEXT,
        note TEXT
      )
    ''');
    await db.insert('repairs', {'id': 'R14', 'fileValue': 1000.0});
    await db.insert('accounts', {'id': 1, 'code': '4000'});
    await db.insert('gl_lines', {
      'account_id': 1,
      'debit': 0.0,
      'credit': 1000.0,
      'repair_id': 'R14',
    });
    await db.insert('purchase_invoices', {
      'id': 'PI1',
      'date': '2026-09-01T00:00:00.000',
      'purchase_type': 'PARTS',
    });
    await db.insert('purchase_invoice_lines', {
      'id': 'PL1',
      'invoice_id': 'PI1',
      'item_name': 'باب أمامي',
      'qty': 2.0,
      'price': 100.0,
      'unit_price': 100.0,
      'total': 200.0,
      'category': 'PARTS',
    });
  });

  tearDown(() async => db.close());

  test('P14 additive cost schema supports used, waste, labor and reversal',
      () async {
    await RepairCostService.ensureSchema(db);
    final cols = await db.rawQuery('PRAGMA table_info(repair_cost_entries)');
    final names = cols.map((e) => e['name']?.toString()).toSet();
    expect(
      names,
      containsAll(<String>{
        'repair_id',
        'cost_type',
        'quantity_used',
        'waste_quantity',
        'unit_cost',
        'total_cost',
        'source_type',
        'source_line_id',
        'employee_id',
        'work_hours',
        'status',
        'reversal_reason',
      }),
    );
  });

  test('P14 profit uses P10 GL revenue and management cost entries', () async {
    await RepairCostService.addManualCost(
      repairId: 'R14',
      costType: RepairCostType.rawMaterial,
      itemName: 'معجون',
      quantityUsed: 2,
      wasteQuantity: 0.5,
      unitCost: 40,
      actorId: 'TEST',
      executor: db,
    );
    await RepairCostService.addManualCost(
      repairId: 'R14',
      costType: RepairCostType.labor,
      itemName: 'فني دهان',
      quantityUsed: 3,
      workHours: 3,
      unitCost: 50,
      actorId: 'TEST',
      executor: db,
    );

    final snapshot = await RepairCostService.loadSnapshot('R14', executor: db);
    expect(snapshot.revenue, 1000.0);
    expect(snapshot.directCost, 250.0);
    expect(snapshot.wasteCost, 20.0);
    expect(snapshot.profit, 750.0);
    expect(snapshot.marginPercent, 75.0);
  });

  test(
      'purchase line allocation cannot exceed purchased quantity and does not post GL',
      () async {
    await RepairCostService.allocatePurchaseLine(
      repairId: 'R14',
      purchaseLineId: 'PL1',
      costType: RepairCostType.parts,
      quantityUsed: 1.5,
      wasteQuantity: 0.25,
      actorId: 'TEST',
      executor: db,
    );
    final candidates =
        await RepairCostService.listAvailablePurchaseLines(executor: db);
    expect(candidates.single.remainingQty, 0.25);

    await expectLater(
      RepairCostService.allocatePurchaseLine(
        repairId: 'R14',
        purchaseLineId: 'PL1',
        costType: RepairCostType.parts,
        quantityUsed: 0.3,
        actorId: 'TEST',
        executor: db,
      ),
      throwsA(isA<StateError>()),
    );

    final source = File(
      'lib/features/repairs/services/repair_cost_service.dart',
    ).readAsStringSync();
    expect(source, contains('recognizedRevenue'));
    expect(source, isNot(contains('postEntryGL')));
    expect(source, isNot(contains("update('gl_")));
    expect(source, isNot(contains("delete('gl_")));
    expect(source, isNot(contains('workCost')));
    expect(source, isNot(contains('incomeAmount')));
  });

  test(
      'reversal preserves original cost row and removes it from active profitability',
      () async {
    final id = await RepairCostService.addManualCost(
      repairId: 'R14',
      costType: RepairCostType.externalService,
      itemName: 'ميزان سيارات خارجي',
      quantityUsed: 1,
      unitCost: 80,
      actorId: 'TEST',
      executor: db,
    );
    expect(
      (await RepairCostService.loadSnapshot('R14', executor: db)).directCost,
      80.0,
    );
    await RepairCostService.reverseEntry(
      entryId: id,
      reason: 'إدخال مكرر',
      actorId: 'TEST',
      executor: db,
    );
    expect(
      (await RepairCostService.loadSnapshot('R14', executor: db)).directCost,
      0.0,
    );
    final rows =
        await db.query('repair_cost_entries', where: 'id=?', whereArgs: [id]);
    expect(rows.single['status'], 'REVERSED');
    expect(rows.single['reversal_reason'], 'إدخال مكرر');
  });

  test('P14 UI and purchase writer contracts are connected and atomic', () {
    final details = File(
      'lib/features/repairs/screens/repair_details_screen.dart',
    ).readAsStringSync();
    final card = File(
      'lib/features/repairs/widgets/repair_profitability_card.dart',
    ).readAsStringSync();
    final purchase = File(
      'lib/features/finance/purchases/services/purchase_invoice_service.dart',
    ).readAsStringSync();
    final tables = File(
      'lib/core/services/db/tables/purchase_invoices_table.dart',
    ).readAsStringSync();
    final paint = File(
      'lib/features/finance/purchases/screens/purchase_paint_screen.dart',
    ).readAsStringSync();

    final provider = File(
      'lib/features/finance/purchases/providers/purchase_provider.dart',
    ).readAsStringSync();

    expect(details, contains('RepairProfitabilityCard'));
    expect(card, contains('تكلفة وربحية الملف'));
    expect(card, contains('تخصيص مشتريات'));
    expect(card, contains('الهدر ضمن التكلفة'));
    expect(purchase,
        contains('await SyncFoundationService.transaction(db, (tx) async'));
    expect(purchase, contains('DBService.postEntryGLOn'));
    expect(
      purchase,
      contains("item['item_name'] ?? item['item'] ?? item['name']"),
    );
    expect(purchase, contains("item['price'] ?? item['unit_price']"));
    expect(tables, contains('category TEXT'));
    expect(paint, contains("purchaseType: 'PAINT'"));
    expect(paint, isNot(contains('supplierId: 9999')));
    expect(provider, contains('FinancialVoidService.voidInvoice'));
    final cancellation =
        File('lib/features/finance/services/financial_void_service.dart')
            .readAsStringSync();
    expect(cancellation, contains('repair_cost_entries rc'));
    expect(cancellation, contains('Reverse repair cost allocations'));
  });
}
