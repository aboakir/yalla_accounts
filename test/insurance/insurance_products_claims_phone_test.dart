import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/claims/screens/insurance_claims_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/screens/insurance_products_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_phone_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/phone.db',
    );
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> pumpPhone(
    WidgetTester tester,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
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
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
  }

  void expectNoLayoutFailure(WidgetTester tester) {
    final errors = <Object>[];
    Object? error;
    while ((error = tester.takeException()) != null) {
      errors.add(error!);
    }
    expect(
      errors.where((value) {
        final text = value.toString();
        return text.contains('overflowed by') ||
            text.contains('RenderBox') ||
            text.contains('RenderFlex');
      }),
      isEmpty,
    );
  }

  testWidgets('insurance products fits a 320px RTL phone', (tester) async {
    await pumpPhone(tester, const InsuranceProductsScreen());
    expect(find.text('منتجات التأمين'), findsOneWidget);
    expectNoLayoutFailure(tester);
  });

  testWidgets('insurance claims fits a 320px RTL phone', (tester) async {
    await pumpPhone(tester, const InsuranceClaimsScreen());
    expect(find.text('مطالبات التأمين'), findsOneWidget);
    expectNoLayoutFailure(tester);
  });
}
