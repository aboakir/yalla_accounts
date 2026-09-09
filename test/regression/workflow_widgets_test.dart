import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/clients/widgets/client_details_dialog.dart';
import 'package:yalla_accounts/features/clients/screens/clients_screen.dart';
import 'package:yalla_accounts/features/suppliers/screens/suppliers_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/vehicles_list_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repairs_screen.dart';
import 'package:yalla_accounts/features/finance/payments/screens/payment_list_screen.dart';
import 'package:yalla_accounts/features/vehicles/models/vehicle.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';
import 'package:yalla_accounts/features/repairs/screens/add_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/screens/journal_entries_screen.dart';
import 'package:yalla_accounts/features/finance/screens/cash_account_screen.dart';
import 'package:yalla_accounts/features/finance/screens/bank_account_screen.dart';
import '../support/accounting_session.dart';

Widget app(Widget child) => ProviderScope(
    child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child));
Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 35)));
    await t.pump(const Duration(milliseconds: 200));
  }
}

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await flush(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test.regression',
      version: '1',
      buildNumber: '1',
      buildSignature: '');
  for (final scenario in ['work', 'parts', 'mixed']) {
    testWidgets('all seven intake steps $scenario, review, save and details',
        (t) async {
      t.view.physicalSize = const Size(430, 932);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      late Directory temp;
      late Database db;
      dynamic session;
      late Client client;
      await t.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        temp = await Directory.systemTemp.createTemp('wizard_regression_');
        db = await DatabaseMigration.initDatabase(
            pathOverride: '${temp.path}/test.db');
        DatabaseMigration.useDatabaseForTesting(db);
        session = await startAccountingSession(db, 'wizard-user');
        final id = await ClientService.insertClient(
            Client(name: 'Wizard Client', type: 'أفراد', phone: '0599000000'));
        client = (await ClientService.getClientById(id))!;
        await VehicleService.insertVehicle(Vehicle(
            number: '1234567', type: 'Toyota', model: '2020', clientId: id));
      });
      try {
        await t.pumpWidget(app(Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const AddRepairScreen())),
                    child: const Text('start'))))));
        await tap(t, find.text('start'));
        await tap(t, find.text('التالي'));
        expect(find.textContaining('اختر العميل أو أضف'), findsOneWidget);
        await t.pump(const Duration(seconds: 5));
        await flush(t);
        await tap(t, find.text('Wizard Client'));
        await tap(t, find.text('التالي'));
        await tap(t, find.text('1234567'));
        await tap(t, find.text('التالي'));
        if (scenario == 'parts') await tap(t, find.text('قطع فقط'));
        if (scenario == 'mixed') await tap(t, find.text('إصلاح + قطع'));
        Future<void> addLine(bool part) async {
          await tap(t, find.text(part ? 'إضافة قطعة' : 'إضافة عمل'));
          await t.enterText(field(part ? 'اسم / وصف القطعة *' : 'وصف العمل *'),
              part ? 'BrakeTest' : 'WorkTest');
          await t.enterText(field('الكمية *'), '2');
          await t.enterText(field('سعر الوحدة *'), part ? '150' : '250');
          await tap(t, find.text('إضافة'));
        }

        if (scenario != 'parts') await addLine(false);
        if (scenario != 'work') await addLine(true);
        await tap(t, find.text('التالي'));
        await t.enterText(field('قراءة العداد *'), '45000');
        await tap(t, find.text('التالي'));
        await tap(t, find.text('لا يوجد ضرر سابق'));
        await tap(t, find.text('التالي'));
        await tap(t, find.text('التالي'));
        expect(find.text('راجع وافتح الملف'), findsOneWidget);
        await tap(t, find.text('السابق'));
        await tap(t, find.text('التالي'));
        await t.ensureVisible(find.text('فتح الملف'));
        await t.tap(find.text('فتح الملف'));
        await t.tap(find.text('فتح الملف'));
        await flush(t);
        for (var wait = 0;
            wait < 20 && find.byType(AddRepairScreen).evaluate().isNotEmpty;
            wait++) {
          await flush(t);
        }
        expect(find.byType(AddRepairScreen), findsNothing,
            reason: t
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .join(' | '));
        final repairs = await t.runAsync(() => RepairsService(db).list());
        expect(repairs, hasLength(1));
        var repair = repairs!.single;
        expect(
            repair.fileValue,
            scenario == 'work'
                ? 500
                : scenario == 'parts'
                    ? 300
                    : 800);
        expect(t.takeException(), isNull);
        await t.pumpWidget(app(ClientDetailsDialog(client: client)));
        await flush(t);
        expect(find.text('Wizard Client'), findsOneWidget);
        expect(find.text('المركبات المرتبطة'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          await PaymentService.insertCanonicalReceipt(
              database: db,
              operationId: 'detail-receipt',
              clientId: client.id!,
              customerName: client.name,
              method: 'cash',
              date: DateTime(2026, 9, 8),
              allocations: [
                ReceiptAllocationInput(repairId: repair.id, amount: 100)
              ],
              unallocatedAmount: 0);
          if (scenario == 'mixed') {
            final photo = File('${temp.path}/photo.png');
            await photo.writeAsBytes(base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='));
            await db.insert('repairs_images', {
              'id': 'regression-photo',
              'repair_id': repair.id,
              'path': photo.path
            });
          }
          repair = (await RepairsService(db).getById(repair.id))!;
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                (call) async => temp.path);
        expect(repair.paidAmount, 100);
        await t.pumpWidget(app(RepairDetailsScreen(repair: repair)));
        await flush(t);
        for (var wait = 0; wait < 6; wait++) {
          await flush(t);
        }
        final labels = t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .join(' ');
        expect(labels, contains('100.00'));
        expect(
            labels,
            contains(scenario == 'work'
                ? '400.00'
                : scenario == 'parts'
                    ? '200.00'
                    : '700.00'));
        Future<void> reveal(String text) async {
          for (var i = 0; i < 14 && find.text(text).evaluate().isEmpty; i++) {
            await t.drag(find.byType(ListView).first, const Offset(0, -450));
            await flush(t);
          }
          expect(find.text(text), findsWidgets);
        }

        if (scenario != 'parts') await reveal('WorkTest');
        if (scenario != 'work') await reveal('BrakeTest');
        if (scenario == 'mixed') expect(repair.imagePaths, isNotEmpty);

        expect(find.byType(RepairDetailsScreen), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await flush(t);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await flush(t);
        await t.runAsync(() async {
          await session.endEphemeralPreviewSession();
          DatabaseMigration.useDatabaseForTesting(null);
          await db.close();
          await temp.delete(recursive: true);
        });
      }
    });
  }
  testWidgets('search screens can close while async loads are in flight',
      (t) async {
    late Directory temp;
    late Database db;
    await t.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      temp = await Directory.systemTemp.createTemp('search_regression_');
      db = await DatabaseMigration.initDatabase(
          pathOverride: '${temp.path}/test.db');
      DatabaseMigration.useDatabaseForTesting(db);
    });
    try {
      for (final screen in <Widget>[
        const ClientsScreen(),
        const SuppliersScreen(),
        const VehiclesListScreen(),
        const RepairsScreen(),
        const PaymentListScreen(),
        const JournalEntriesScreen(),
        const CashAccountScreen(),
        const BankAccountScreen()
      ]) {
        await t.pumpWidget(app(screen));
        await t.pump();
        final text = find.byType(TextField);
        if (text.evaluate().isNotEmpty) {
          await t.enterText(text.first, 'test');
          await t.enterText(text.first, "' % _");
        }
        await t.pumpWidget(const SizedBox.shrink());
        await flush(t);
        expect(t.takeException(), isNull,
            reason: screen.runtimeType.toString());
      }
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      await flush(t);
      await t.runAsync(() async {
        DatabaseMigration.useDatabaseForTesting(null);
        await db.close();
        await temp.delete(recursive: true);
      });
    }
  });
}
