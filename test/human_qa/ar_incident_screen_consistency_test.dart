import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/repairs/screens/vehicles_arrears_screen.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  Future<void> seed() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseMigration.useDatabaseForTesting(db);
    await db.execute(
      'CREATE TABLE repairs (id TEXT PRIMARY KEY, fileValue REAL, '
      'vehicleType TEXT, vehicleModel TEXT, vehicleNumber TEXT, '
      'beneficiaryType TEXT, beneficiaryName TEXT, receivedDate TEXT)',
    );
    await db.execute(
      'CREATE TABLE accounts (id INTEGER PRIMARY KEY, code TEXT)',
    );
    await db.execute(
      'CREATE TABLE gl_entries (id INTEGER PRIMARY KEY, '
      'source TEXT, reversal_of INTEGER, date TEXT, note TEXT)',
    );
    await db.execute(
      'CREATE TABLE gl_lines (entry_id INTEGER, repair_id TEXT, '
      'account_id INTEGER, debit REAL, credit REAL)',
    );
    await db.insert('repairs', {
      'id': 'AR-BMW',
      'fileValue': 30900.0,
      'vehicleType': 'BMW 520E',
      'vehicleModel': '2020',
      'vehicleNumber': '22222',
      'beneficiaryType': 'ط·آ£ط¸ظ¾ط·آ±ط·آ§ط·آ¯',
      'beneficiaryName': 'AR incident fixture',
      'receivedDate': '2025-08-20T00:00:00',
    });
    for (final a in [
      {'id': 1, 'code': '1200.C1'},
      {'id': 2, 'code': '4000'},
      {'id': 3, 'code': '1000'},
    ]) {
      await db.insert('accounts', a);
    }
    await db.insert('gl_entries', {'id': 1, 'source': 'INVOICE'});
    await db.insert('gl_entries', {'id': 2, 'source': 'PAYMENT'});
    for (final line in [
      {'entry_id': 1, 'account_id': 1, 'debit': 30900.0, 'credit': 0.0},
      {'entry_id': 1, 'account_id': 2, 'debit': 0.0, 'credit': 30900.0},
      {'entry_id': 2, 'account_id': 3, 'debit': 25900.0, 'credit': 0.0},
      {'entry_id': 2, 'account_id': 1, 'debit': 0.0, 'credit': 25900.0},
    ]) {
      await db.insert('gl_lines', {...line, 'repair_id': 'AR-BMW'});
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(seed);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('ar'),
          supportedLocales: [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: VehiclesArrearsScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  tearDown(() async {
    DatabaseMigration.useDatabaseForTesting(null);
    await db.close();
  });

  testWidgets('AR incident: mobile BMW card agrees with repair truth', (
    tester,
  ) async {
    await mount(tester);
    final truth = await tester.runAsync(
      () => RepairFinancialTruthService.load('AR-BMW', executor: db),
    );
    expect(truth!.paid, 25900);
    expect(truth.remaining, 5000);
    expect(
      find.textContaining('25,900.00', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('5,000.00', findRichText: true),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AR incident: resume refreshes a committed final receipt', (
    tester,
  ) async {
    await mount(tester);
    await tester.runAsync(() async {
      await db.transaction((tx) async {
        await tx.insert('gl_entries', {'id': 3, 'source': 'VOUCHER'});
        await tx.insert('gl_lines', {
          'entry_id': 3,
          'repair_id': 'AR-BMW',
          'account_id': 1,
          'debit': 0.0,
          'credit': 5000.0,
        });
        await tx.insert('gl_lines', {
          'entry_id': 3,
          'repair_id': 'AR-BMW',
          'account_id': 3,
          'debit': 5000.0,
          'credit': 0.0,
        });
      });
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(
      find.textContaining('30,900.00', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('25,900.00', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('5,000.00', findRichText: true),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AR incident: reversal is not retained as received money', (
    tester,
  ) async {
    await mount(tester);
    await tester.runAsync(() async {
      await db.insert('gl_entries', {
        'id': 3,
        'source': 'REVERSAL',
        'reversal_of': 2,
      });
      await db.insert('gl_lines', {
        'entry_id': 3,
        'repair_id': 'AR-BMW',
        'account_id': 1,
        'debit': 25900.0,
        'credit': 0.0,
      });
      await db.insert('gl_lines', {
        'entry_id': 3,
        'repair_id': 'AR-BMW',
        'account_id': 3,
        'debit': 0.0,
        'credit': 25900.0,
      });
    });
    await tester.tap(find.byIcon(Icons.refresh));
    await settle(tester);
    final truth = await tester.runAsync(
      () => RepairFinancialTruthService.load('AR-BMW', executor: db),
    );
    expect(truth!.paid, 0);
    expect(truth.remaining, 30900);
    expect(
      find.textContaining('30,900.00', findRichText: true),
      findsNWidgets(3),
    );
    expect(tester.takeException(), isNull);
  });
}
