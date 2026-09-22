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
import 'package:yalla_accounts/features/clients/screens/clients_screen.dart';
import 'package:yalla_accounts/features/suppliers/screens/suppliers_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/vehicles_list_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repairs_screen.dart';
import 'package:yalla_accounts/features/finance/screens/journal_entries_screen.dart';
import 'package:yalla_accounts/features/finance/screens/cash_account_screen.dart';
import 'package:yalla_accounts/features/finance/screens/bank_account_screen.dart';
import 'package:yalla_accounts/features/employees/screens/add_employee_screen.dart';
import 'package:yalla_accounts/features/employees/screens/employees_list_screen.dart';
import 'package:yalla_accounts/features/employees/screens/attendance_screen.dart';
import 'package:yalla_accounts/features/vouchers/screens/payment_voucher_screen.dart';
import 'package:yalla_accounts/features/vouchers/screens/receipt_voucher_screen.dart';
import 'package:yalla_accounts/features/finance/purchases/screens/purchase_create_screen.dart';
import 'package:yalla_accounts/features/finance/purchases/screens/purchases_list_screen.dart';
import 'package:yalla_accounts/features/parties/screens/parties_screen.dart';
import 'package:yalla_accounts/features/settings/screens/commercial_settings_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/calculator/screens/insurance_calculator_screen.dart';

import 'package:yalla_accounts/features/employees/screens/employee_dashboard_screen.dart';
import 'package:yalla_accounts/features/settings/screens/security_data_screen.dart';
import 'package:yalla_accounts/features/settings/screens/workshop_settings_screen.dart';
import 'package:yalla_accounts/features/settings/screens/audit_trail_screen.dart';
import 'package:yalla_accounts/features/finance/screens/finance_dashboard_screen.dart';
import 'package:yalla_accounts/features/finance/screens/accounts_receivable_screen.dart';
import 'package:yalla_accounts/features/finance/screens/collection_dashboard_screen.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_browser_screen.dart';
import 'package:yalla_accounts/features/finance/reports/screens/income_statement_screen.dart';
import 'package:yalla_accounts/features/finance/reports/screens/balance_sheet_screen.dart';
import 'package:yalla_accounts/features/finance/reports/screens/cash_flow_screen.dart';
import 'package:yalla_accounts/features/raw_materials/screens/raw_materials_screen.dart';

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
    testWidgets('Stage36 primary screens $size including keyboard', (t) async {
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
      final failures = <String>[];
      try {
        for (final screen in <Widget>[
          ClientsScreen(),
          SuppliersScreen(),
          VehiclesListScreen(),
          RepairsScreen(),
          JournalEntriesScreen(),
          CashAccountScreen(),
          BankAccountScreen(),
          AddEmployeeScreen(),
          EmployeesListScreen(),
          AttendanceScreen(),
          PaymentVoucherScreen(),
          ReceiptVoucherScreen(),
          PurchaseCreateScreen(),
          PurchasesListScreen(),
          PartiesScreen(),
          CommercialSettingsScreen(),
          InsuranceCalculatorScreen(),
          EmployeeDashboardScreen(),
          SecurityDataScreen(),
          WorkshopSettingsScreen(),
          AuditTrailScreen(),
          FinanceDashboardScreen(),
          AccountsReceivableScreen(),
          CollectionDashboardScreen(),
          GLBrowserScreen(),
          IncomeStatementScreen(),
          BalanceSheetScreen(),
          CashFlowScreen(),
          RawMaterialsScreen(),
        ]) {
          final originalError = FlutterError.onError;
          FlutterError.onError = (details) {
            failures.add('${screen.runtimeType}: ${details.toString()}');
          };
          try {
            if (screen is SecurityDataScreen) {
              await t.runAsync(() async {
                await t.pumpWidget(auditApp(RepaintBoundary(
                    key: const ValueKey('stage36-capture'), child: screen)));
                await Future<void>.delayed(const Duration(milliseconds: 300));
              });
            } else {
              await t.pumpWidget(auditApp(RepaintBoundary(
                  key: const ValueKey('stage36-capture'), child: screen)));
            }
            await flush(t);
            if (screen is SecurityDataScreen) {
              expect(find.text('حفظ الإعدادات'), findsOneWidget);
            }
            void capture() {
              Object? e;
              while ((e = t.takeException()) != null) {
                failures.add('${screen.runtimeType}: $e');
              }
            }

            capture();
            if (size.width == 430) {
              await captureAuditScreen(t, screen.runtimeType.toString());
            }
            if (screen is SuppliersScreen) {
              // v85 adds shipped insurer suppliers. Locate the fixture through
              // the real search UI instead of assuming it is in the first viewport.
              final supplierSearch = find.descendant(
                  of: find.byType(SuppliersScreen),
                  matching: find.byType(TextField));
              expect(supplierSearch, findsOneWidget);
              await t.enterText(supplierSearch, 'مورد مواد دهان');
              await flush(t);
              final supplierLabel = find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    (widget.data ?? '').contains('مورد مواد دهان'),
              );
              expect(supplierLabel, findsWidgets);
              final supplierInk = find.ancestor(
                of: supplierLabel.first,
                matching: find.byType(InkWell),
              );
              expect(supplierInk, findsOneWidget);
              await t.tap(supplierInk);
              await t.pump();
              await t.pump(const Duration(milliseconds: 500));
              expect(find.text('كشف حساب المورد'), findsOneWidget);
              t.view.viewInsets = const FakeViewPadding(bottom: 120);
              await t.pump();
              capture();
              t.state<NavigatorState>(find.byType(Navigator).first).pop();
              t.view.viewInsets = FakeViewPadding.zero;
              await flush(t);
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
