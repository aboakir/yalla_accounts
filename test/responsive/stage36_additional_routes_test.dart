import 'package:yalla_accounts/features/auth/screens/login_screen.dart';
import 'package:yalla_accounts/features/auth/screens/manage_users_screen.dart';
import 'package:yalla_accounts/features/auth/screens/register_user_screen.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
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

import 'package:yalla_accounts/features/repairs/screens/repairs_overview_screen.dart'
    as route0;
import 'package:yalla_accounts/features/repairs/screens/repair_reports_screen.dart'
    as route1;
import 'package:yalla_accounts/features/repairs/screens/repair_analytics_screen.dart'
    as route2;
import 'package:yalla_accounts/features/repairs/screens/vehicles_arrears_screen.dart'
    as route3;
import 'package:yalla_accounts/features/repairs/screens/repairs_and_ar_screen.dart'
    as route4;
import 'package:yalla_accounts/features/employees/screens/salary_screen.dart'
    as route5;
import 'package:yalla_accounts/features/finance/screens/general_journal_screen.dart'
    as route6;
import 'package:yalla_accounts/features/finance/screens/account_ledger_screen.dart'
    as route7;
import 'package:yalla_accounts/features/vouchers/screens/payment_vouchers_list_screen.dart'
    as route8;
import 'package:yalla_accounts/features/vouchers/screens/receipt_vouchers_list_screen.dart'
    as route9;
import 'package:yalla_accounts/features/finance/purchases/screens/purchases_dashboard_screen.dart'
    as route10;
import 'package:yalla_accounts/features/finance/purchases/screens/purchase_tools_screen.dart'
    as route11;
import 'package:yalla_accounts/features/finance/purchases/screens/purchase_insurance_screen.dart'
    as route12;
import 'package:yalla_accounts/features/finance/purchases/screens/purchase_other_screen.dart'
    as route13;
import 'package:yalla_accounts/features/finance/purchases/screens/supplier_payments_screen.dart'
    as route14;
import 'package:yalla_accounts/features/cheques/screens/cheques_dashboard_screen.dart'
    as route15;
import 'package:yalla_accounts/features/cheques/screens/cheque_add_screen.dart'
    as route16;
import 'package:yalla_accounts/features/cheques/screens/cheques_list_screen.dart'
    as route17;
import 'package:yalla_accounts/features/cheques/screens/cheques_incoming_screen.dart'
    as route18;
import 'package:yalla_accounts/features/cheques/screens/cheques_outgoing_screen.dart'
    as route19;
import 'package:yalla_accounts/features/cheques/screens/cheques_collection_screen.dart'
    as route20;
import 'package:yalla_accounts/features/cheques/screens/cheques_collected_screen.dart'
    as route21;
import 'package:yalla_accounts/features/cheques/screens/cheques_returned_screen.dart'
    as route22;
import 'package:yalla_accounts/features/cheques/screens/cheques_cancelled_screen.dart'
    as route23;
import 'package:yalla_accounts/features/cheques/screens/cheques_postdated_screen.dart'
    as route24;
import 'package:yalla_accounts/features/cheques/screens/cheques_report_screen.dart'
    as route25;
import 'package:yalla_accounts/features/finance/purchases/screens/suppliers_aging_screen.dart'
    as route26;
import 'package:yalla_accounts/features/finance/purchases/screens/purchases_gl_audit_screen.dart'
    as route27;
import 'package:yalla_accounts/features/finance/purchases/screens/unposted_purchases_screen.dart'
    as route28;
import 'package:yalla_accounts/features/parties/screens/parties_screen.dart'
    as route29;
import 'package:yalla_accounts/features/clients/screens/client_edit_screen.dart'
    as route30;
import 'package:yalla_accounts/features/insurance/screens/insurance_invoice_list_screen.dart'
    as route31;
import 'package:yalla_accounts/features/raw_materials/screens/raw_material_list_screen.dart'
    as route32;
import 'package:yalla_accounts/features/suppliers/screens/suppliers_payables_list_screen.dart'
    as route33;
import 'package:yalla_accounts/features/suppliers/screens/suppliers_list_screen.dart'
    as route34;
import 'package:yalla_accounts/features/suppliers/screens/supplier_form_screen.dart'
    as route35;
import 'package:yalla_accounts/features/suppliers/screens/suppliers_debts_screen.dart'
    as route36;
import 'package:yalla_accounts/features/reports/screens/reports_dashboard_screen.dart'
    as route37;
import 'package:yalla_accounts/features/reports/screens/trial_balance_screen.dart'
    as route38;
import 'package:yalla_accounts/features/finance/reports/screens/ar_aging_screen.dart'
    as route39;
import 'package:yalla_accounts/features/employees/screens/attendance_report_screen.dart'
    as route40;
import 'package:yalla_accounts/features/employees/screens/advances_report_screen.dart'
    as route41;
import 'package:yalla_accounts/features/employees/screens/payroll_report_screen.dart'
    as route42;
import 'package:yalla_accounts/features/search/screens/global_search_screen.dart'
    as route43;
import 'package:yalla_accounts/features/support/screens/technical_support_screen.dart'
    as route44;
import 'package:yalla_accounts/features/subscription/screens/subscription_screen.dart'
    as route45;
import 'package:yalla_accounts/features/subscription/screens/current_subscription_screen.dart'
    as route46;
import 'package:yalla_accounts/features/subscription/screens/pending_subscriptions_screen.dart'
    as route47;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DeviceInfoPlatform.instance = _AuditDeviceInfo();
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
    testWidgets('Stage36 additional routes $size including keyboard',
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
      final failures = <String>[];
      try {
        for (final screen in <Widget>[
          const LoginScreen(),
          const ManageUsersScreen(),
          const RegisterUserScreen(),
          route0.RepairsOverviewScreen(),
          route1.RepairReportsScreen(),
          route2.RepairAnalyticsScreen(),
          route3.VehiclesArrearsScreen(),
          route4.RepairsAndARScreen(),
          route5.SalaryScreen(),
          route6.GeneralJournalScreen(),
          route7.AccountLedgerScreen(),
          route8.PaymentVoucherListScreen(),
          route9.ReceiptVoucherListScreen(),
          route10.PurchasesDashboardScreen(),
          route11.PurchaseToolsScreen(),
          route12.PurchaseInsuranceScreen(),
          route13.PurchaseOtherScreen(),
          route14.SupplierPaymentsScreen(),
          route15.ChequesDashboardScreen(),
          route16.ChequeAddScreen(),
          route17.ChequesListScreen(),
          route18.ChequesIncomingScreen(),
          route19.ChequesOutgoingScreen(),
          route20.ChequesCollectionScreen(),
          route21.ChequesCollectedScreen(),
          route22.ChequesReturnedScreen(),
          route23.ChequesCancelledScreen(),
          route24.ChequesPostdatedScreen(),
          route25.ChequesReportScreen(),
          route26.SuppliersAgingScreen(),
          route27.PurchasesGLAuditScreen(),
          route28.UnpostedPurchasesScreen(),
          route29.PartyFormScreen(),
          route30.ClientEditScreen(),
          route31.InsuranceInvoiceListScreen(),
          route32.RawMaterialListScreen(),
          route33.SupplierPayablesListScreen(),
          route34.SupplierListScreen(),
          route35.SupplierFormScreen(),
          route36.SuppliersDebtsScreen(),
          route37.ReportsDashboardScreen(),
          route38.TrialBalanceScreen(),
          route39.ARAgingScreen(),
          route40.AttendanceReportScreen(),
          route41.AdvancesReportScreen(),
          route42.PayrollReportScreen(),
          route43.GlobalSearchScreen(),
          route44.TechnicalSupportScreen(),
          route45.SubscriptionScreen(),
          route46.CurrentSubscriptionScreen(),
          route47.PendingSubscriptionsScreen()
        ]) {
          final originalError = FlutterError.onError;
          FlutterError.onError = (details) {
            failures.add('${screen.runtimeType}: ${details.toString()}');
          };
          try {
            await t.pumpWidget(auditApp(RepaintBoundary(
                key: const ValueKey('stage36-capture'), child: screen)));
            await flush(t);
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

class _AuditDeviceInfo extends DeviceInfoPlatform {
  @override
  Future<BaseDeviceInfo> deviceInfo() async => WindowsDeviceInfo(
        computerName: 'stage36-test',
        numberOfCores: 1,
        systemMemoryInMegabytes: 1,
        userName: 'stage36-test',
        majorVersion: 1,
        minorVersion: 1,
        buildNumber: 1,
        platformId: 1,
        csdVersion: 'stage36-test',
        servicePackMajor: 1,
        servicePackMinor: 1,
        suitMask: 1,
        productType: 1,
        reserved: 1,
        buildLab: 'stage36-test',
        buildLabEx: 'stage36-test',
        digitalProductId: Uint8List(0),
        displayVersion: 'stage36-test',
        editionId: 'stage36-test',
        installDate: DateTime(2026),
        productId: 'stage36-test',
        productName: 'stage36-test',
        registeredOwner: 'stage36-test',
        releaseId: 'stage36-test',
        deviceId: 'stage36-test',
      );
}
