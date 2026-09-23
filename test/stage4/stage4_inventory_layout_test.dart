import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
  late int itemId;
  late int warehouseId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('inventory_layout_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(dir.path, 'layout.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);

    itemId = await CanonicalInventoryService.createItem(
      name: 'Primer Test',
      itemKind: 'RAW_MATERIAL',
      unit: 'liter',
      sku: 'LAYOUT-PRIMER',
      category: 'PAINT',
    );
    warehouseId = await CanonicalInventoryService.createWarehouse(
      code: 'LAYOUT',
      name: 'Layout Warehouse',
    );
    await CanonicalInventoryService.recordMovement(
      itemId: itemId,
      warehouseId: warehouseId,
      movementType: 'PURCHASE_RECEIPT',
      onHandDelta: 10,
      unitCost: 5,
      landedCost: 5,
      sourceEntityType: 'LAYOUT_SEED',
      sourceReference: 'LAYOUT-1',
    );
    await InventoryOperationsService.setReorderLevel(
      itemId: itemId,
      warehouseId: warehouseId,
      level: 12,
    );
  });

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    if (db.isOpen) await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget child,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: child,
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
  }

  testWidgets('canonical inventory fits Windows 1280x800', (tester) async {
    await pumpAt(
      tester,
      const Size(1280, 800),
      const InventoryListScreen(),
    );
    expect(find.text('إدارة المخزون'), findsOneWidget);
    expect(find.text('Primer Test'), findsOneWidget);
    expect(find.text('وصل الصنف إلى حد إعادة الطلب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canonical raw materials fit 320px RTL phone', (tester) async {
    await pumpAt(
      tester,
      const Size(320, 700),
      const InventoryListScreen(itemKind: 'RAW_MATERIAL'),
    );
    expect(find.text('المواد والمخزون'), findsOneWidget);
    expect(find.text('Primer Test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('inventory routes and sidebar use canonical inventory', () {
    final routes = File(
      'lib/core/routes/app_routes.dart',
    ).readAsStringSync();
    final sidebar = File(
      'lib/core/widgets/sidebar/yalla_sidebar.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/inventory/screens/inventory_list_screen.dart',
    ).readAsStringSync();

    expect(routes, contains('const InventoryListScreen()'));
    expect(
      routes,
      contains("const InventoryListScreen(itemKind: 'RAW_MATERIAL')"),
    );
    expect(
      routes,
      isNot(contains("_under(settings, 'شاشة الجرد والمخزون')")),
    );
    expect(sidebar, contains('المخزون والجرد'));
    expect(screen, contains('CanonicalInventoryService'));
    expect(screen, contains('InventoryOperationsService'));
    expect(
      RegExp(r'\bInventoryService\.').hasMatch(screen),
      isFalse,
      reason: 'Legacy InventoryService must not power canonical inventory UI.',
    );
  });
}
