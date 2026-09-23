import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/inventory/screens/inventory_list_screen.dart';
import 'package:yalla_accounts/features/inventory/services/canonical_inventory_service.dart';
import 'package:yalla_accounts/features/inventory/services/inventory_operations_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late Database db;
  late int warehouseId;
  late int primerId;
  late int panelId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('stage5_inventory_report_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'report.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);

    primerId = await CanonicalInventoryService.createItem(
      name: 'Primer Report',
      itemKind: 'RAW_MATERIAL',
      unit: 'liter',
      sku: 'RPT-PRIMER',
      category: 'PAINT',
    );
    panelId = await CanonicalInventoryService.createItem(
      name: 'Body Panel Report',
      itemKind: 'PART',
      unit: 'pcs',
      sku: 'RPT-PANEL',
      category: 'PARTS',
    );
    warehouseId = await CanonicalInventoryService.createWarehouse(
      code: 'REPORT',
      name: 'Report Warehouse',
    );

    await CanonicalInventoryService.recordMovement(
      itemId: primerId,
      warehouseId: warehouseId,
      movementType: 'PURCHASE_RECEIPT',
      onHandDelta: 100,
      unitCost: 10,
      landedCost: 10,
      sourceEntityType: 'REPORT_SEED',
      sourceReference: 'RPT-P1',
    );
    await CanonicalInventoryService.recordMovement(
      itemId: primerId,
      warehouseId: warehouseId,
      movementType: 'PURCHASE_RECEIPT',
      onHandDelta: 50,
      unitCost: 20,
      landedCost: 20,
      sourceEntityType: 'REPORT_SEED',
      sourceReference: 'RPT-P2',
    );
    await CanonicalInventoryService.recordMovement(
      itemId: panelId,
      warehouseId: warehouseId,
      movementType: 'PURCHASE_RECEIPT',
      onHandDelta: 5,
      unitCost: 100,
      landedCost: 100,
      sourceEntityType: 'REPORT_SEED',
      sourceReference: 'RPT-P3',
    );
    await InventoryOperationsService.setReorderLevel(
      itemId: primerId,
      warehouseId: warehouseId,
      level: 200,
    );
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets(
      'Stage 5 inventory report shows Stage 4 valuation and keeps search focus',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: InventoryListScreen(),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 250));

    String summaryText(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    expect(summaryText('inventory-report-item-count'), 'الأصناف: 2');
    expect(
        summaryText('inventory-report-total-value'), 'قيمة المخزون: 2500.00');
    expect(summaryText('inventory-report-reorder-count'), 'إعادة الطلب: 1');
    expect(tester.takeException(), isNull);

    final search = find.byKey(const ValueKey('inventory-report-search'));
    expect(search, findsOneWidget);
    await tester.tap(search);
    await tester.enterText(search, 'RPT-PRIMER');
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, 'RPT-PRIMER');
    expect(summaryText('inventory-report-item-count'), 'الأصناف: 1');
    expect(
        summaryText('inventory-report-total-value'), 'قيمة المخزون: 2000.00');
    expect(tester.takeException(), isNull);

    await tester.enterText(search, 'NO-MATCH');
    await tester.pump();
    final after = tester.widget<EditableText>(find.byType(EditableText));
    expect(after.focusNode.hasFocus, isTrue);
    expect(summaryText('inventory-report-item-count'), 'الأصناف: 0');
    expect(summaryText('inventory-report-total-value'), 'قيمة المخزون: 0.00');
    expect(tester.takeException(), isNull);
  });

  test('Stage 5 inventory PDF uses canonical valuation snapshot', () async {
    final primer = await InventoryOperationsService.valuation(
      itemId: primerId,
      warehouseId: warehouseId,
      executor: db,
    );
    final panel = await InventoryOperationsService.valuation(
      itemId: panelId,
      warehouseId: warehouseId,
      executor: db,
    );
    expect(primer.onHand, closeTo(150, 0.001));
    expect(primer.stockValue, closeTo(2000, 0.01));
    expect(primer.averageUnitCost, closeTo(13.333333, 0.001));
    expect(panel.stockValue, closeTo(500, 0.01));

    final bytes = await YallaPdfService.generateTablePdf(
      title: 'تقرير المخزون',
      headers: const [
        'الرمز',
        'الصنف',
        'الرصيد',
        'متوسط التكلفة',
        'القيمة',
      ],
      rows: [
        [
          'RPT-PRIMER',
          'Primer Report',
          primer.onHand.toStringAsFixed(2),
          primer.averageUnitCost.toStringAsFixed(2),
          primer.stockValue.toStringAsFixed(2),
        ],
        [
          'RPT-PANEL',
          'Body Panel Report',
          panel.onHand.toStringAsFixed(2),
          panel.averageUnitCost.toStringAsFixed(2),
          panel.stockValue.toStringAsFixed(2),
        ],
      ],
    );
    expect(bytes.length, greaterThan(100));
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });
}
