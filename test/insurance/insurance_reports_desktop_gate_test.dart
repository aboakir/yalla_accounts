import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/claims/screens/insurance_claims_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/screens/insurance_products_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/reports/screens/insurance_reports_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('insurance dashboard totals and PDF use canonical policy truth',
      () async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final temp = await Directory.systemTemp.createTemp('insurance_report_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: p.join(temp.path, 'report.db'),
    );
    DatabaseMigration.useDatabaseForTesting(db);
    addTearDown(() async {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    const now = '2026-09-23T08:00:00Z';
    await db.insert('insurance_policies', {
      'id': 'P1',
      'created_at': now,
      'updated_at': now,
      'vehicle_plate': '123-45-678',
      'vehicle_make': 'Kia',
      'vehicle_model_year': '2024',
      'engine_cc': '1600',
      'insured_name': 'عميل تأمين',
      'insured_phone': '0599000000',
      'company_name': 'شركة اختبار',
      'start_date': '2026-01-01',
      'end_date': '2026-10-10',
      'buy_price': 2000.0,
      'sell_price': 2400.0,
      'payment_type': 'CASH',
      'cash_amount': 0.0,
      'policy_number': 'POL-100',
      'status': 'ACTIVE',
      'posting_status': 'POSTED',
      'net_sale_amount': 2400.0,
      'net_insurer_payable': 2000.0,
      'gross_profit': 400.0,
    });
    await db.insert('insurance_policy_payments', {
      'id': 'PAY-CUST-1',
      'policy_id': 'P1',
      'direction': 'CUSTOMER_RECEIPT',
      'amount': 1000.0,
      'status': 'POSTED',
      'created_at': now,
    });
    await db.insert('insurance_policy_payments', {
      'id': 'PAY-INS-1',
      'policy_id': 'P1',
      'direction': 'INSURER_PAYMENT',
      'amount': 500.0,
      'status': 'POSTED',
      'created_at': now,
    });
    await db.insert('insurance_claims', {
      'id': 'CLM-1',
      'claim_number': 'CLM-100',
      'policy_id': 'P1',
      'status': 'OPEN',
      'reported_at': now,
      'created_at': now,
      'updated_at': now,
    });

    final summary = await InsuranceDashboardService.summary(
      asOf: DateTime(2026, 9, 23),
      executor: db,
    );
    expect(summary.activePolicies, 1);
    expect(summary.expiringSoon, 1);
    expect(summary.openClaims, 1);
    expect(summary.totalSales, 2400);
    expect(summary.totalCost, 2000);
    expect(summary.grossProfit, 400);
    expect(summary.customerReceivable, 1400);
    expect(summary.insurerPayable, 1500);

    final rows = await InsuranceDashboardService.policies(executor: db);
    expect(rows, hasLength(1));
    expect(rows.single.number, 'POL-100');
    expect(rows.single.sale, 2400);

    final bytes = await YallaPdfService.generateTablePdf(
      title: 'تقرير وثائق التأمين',
      headers: const ['رقم الوثيقة', 'المؤمن', 'البيع'],
      rows: [
        [rows.single.number, rows.single.insuredName, '2400.00'],
      ],
    );
    expect(bytes.length, greaterThan(100));
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });

  group('insurance desktop layout gate', () {
    late Directory temp;
    late Database db;

    setUp(() async {
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      temp = await Directory.systemTemp.createTemp('insurance_desktop_');
      db = await DatabaseMigration.initDatabase(
        pathOverride: p.join(temp.path, 'desktop.db'),
      );
      DatabaseMigration.useDatabaseForTesting(db);
    });

    tearDown(() async {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    Future<void> pumpDesktop(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1280, 800);
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
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    }

    testWidgets('products and claims render on Windows-class width',
        (tester) async {
      await pumpDesktop(tester, const InsuranceProductsScreen());
      expect(find.text('منتجات التأمين'), findsWidgets);

      await pumpDesktop(tester, const InsuranceClaimsScreen());
      expect(find.text('مطالبات التأمين'), findsWidgets);
    });

    testWidgets('insurance reports render on Windows-class width',
        (tester) async {
      await pumpDesktop(tester, const InsuranceReportsScreen());
      expect(find.text('تقارير التأمين'), findsOneWidget);
      expect(find.text('الوثائق السارية'), findsOneWidget);
      expect(find.text('إجمالي المبيعات'), findsOneWidget);
      expect(find.text('الربح الإجمالي'), findsOneWidget);
    });
  });
}
