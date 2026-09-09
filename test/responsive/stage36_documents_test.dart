import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import '../regression/workflow_widgets_test.dart' show flush;
import 'stage36_support.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/finance/purchases/screens/purchase_details_screen.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/widgets/client_details_dialog.dart';
import 'package:yalla_accounts/features/clients/widgets/edit_client_dialog.dart';
import 'package:yalla_accounts/features/suppliers/screens/supplier_account_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  PackageInfo.setMockInitialValues(
      appName: 'Audit',
      packageName: 'audit',
      version: '1',
      buildNumber: '1',
      buildSignature: '');
  for (final size in [
    const Size(430, 932),
    const Size(390, 844),
    const Size(844, 390)
  ]) {
    testWidgets('Stage36 document details and dialogs $size including keyboard',
        (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      late Directory dir;
      late Database db;
      await t.runAsync(() async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        dir = await Directory.systemTemp.createTemp('stage36_');
        YallaStorageService.useRootDirectoryForTesting(
            Directory('${dir.path}/files'));
        db = await DatabaseMigration.initDatabase(
            pathOverride: '${dir.path}/audit.db');
        DatabaseMigration.useDatabaseForTesting(db);
        await seedAuditData(db);
      });
      final clients = await t.runAsync(() => db.query('clients', limit: 1));
      final repairs = await t.runAsync(() => db.query('repairs', limit: 1));
      final suppliers = await t.runAsync(() => db.query('suppliers', limit: 1));
      final client = Client.fromMap(clients!.first);
      final repair = Repair.fromMap(repairs!.first);
      final failures = <String>[];
      try {
        for (final screen in <Widget>[
          RepairDetailsScreen(repair: repair),
          const PurchaseDetailsScreen(invoiceId: 'stage36-purchase'),
          SupplierAccountScreen(
              supplierId: '${suppliers!.first['id']}',
              supplierName: '${suppliers.first['name']}'),
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => ClientDetailsDialog(client: client)),
                      child: const Text('افتح الحوار')))),
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => EditClientDialog(client: client)),
                      child: const Text('افتح الحوار')))),
        ]) {
          final originalError = FlutterError.onError;
          FlutterError.onError = (details) {
            failures.add('${screen.runtimeType}: ${details.toString()}');
          };
          try {
            await t.pumpWidget(auditApp(RepaintBoundary(
                key: const ValueKey('stage36-capture'), child: screen)));
            await flush(t);
            if (find.text('افتح الحوار').evaluate().isNotEmpty) {
              await t.tap(find.text('افتح الحوار'));
              await flush(t);
            }
            void capture() {
              Object? e;
              while ((e = t.takeException()) != null) {
                failures.add('${screen.runtimeType}: $e');
              }
            }

            capture();
            if (size.width == 430 && screen is! Builder) {
              await captureAuditScreen(t, screen.runtimeType.toString());
            }
            final inputs = find.byType(TextField).hitTestable();
            if (inputs.evaluate().isNotEmpty) {
              await t.tap(inputs.first);
              t.view.viewInsets =
                  FakeViewPadding(bottom: size.height > 500 ? 300 : 120);
              await t.pump(const Duration(milliseconds: 300));
              capture();
              t.view.viewInsets = FakeViewPadding.zero;
              await t.pump();
            }
            final scroll = find.byType(Scrollable).hitTestable();
            if (scroll.evaluate().isNotEmpty) {
              await t.drag(scroll.first, const Offset(0, -450));
              await t.pump();
              capture();
            }
            await t.pumpWidget(const SizedBox());
            await flush(t);
            capture();
          } catch (error, stack) {
            failures.add('${screen.runtimeType}: $error\n$stack');
          } finally {
            FlutterError.onError = originalError;
          }
        }
        expect(failures, isEmpty, reason: failures.join(' | '));
      } finally {
        await t.pumpWidget(const SizedBox());
        await flush(t);
        await t.runAsync(() async {
          YallaStorageService.useRootDirectoryForTesting(null);
          DatabaseMigration.useDatabaseForTesting(null);
          await db.close();
          await dir.delete(recursive: true);
        });
      }
    });
  }
}
