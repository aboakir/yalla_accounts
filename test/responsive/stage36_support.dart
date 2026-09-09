import 'package:yalla_accounts/core/services/db/tables/owner_bootstrap_tables.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import '../support/accounting_session.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_route_frame.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_theme.dart';
import 'package:yalla_accounts/shared/widgets/yalla_mobile_adaptive.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/suppliers/models/supplier.dart';
import 'package:yalla_accounts/features/suppliers/services/supplier_service.dart';
import 'package:yalla_accounts/features/vehicles/models/vehicle.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

Future<void> loadAuditFonts() async {
  await (FontLoader('AuditArabicFallback')
        ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf')))
      .load();
  await (FontLoader('Cairo')
        ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Cairo-Bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Widget auditApp(Widget screen) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => AppUser(
              id: 'stage36-owner',
              name: 'مالك الاختبار',
              email: '',
              role: 'owner',
              status: 'active',
              createdAt: DateTime(2026)))
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'Cairo',
              fontFamilyFallback: const ['AuditArabicFallback'],
              colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
              appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
              visualDensity: VisualDensity.adaptivePlatformDensity),
          builder: (context, child) => MediaQuery.sizeOf(context).width >= 600
              ? child!
              : Theme(
                  data: YallaMobileTheme.from(Theme.of(context)),
                  child: YallaMobilePage(child: child!)),
          home: YallaMobileRouteFrame(
              routeName: (screen is RepaintBoundary
                          ? screen.child.runtimeType.toString()
                          : screen.runtimeType.toString()) ==
                      'RepairsScreen'
                  ? '/repairs/list'
                  : '/stage36',
              child: screen),
        ));

Future<void> seedAuditData(Database db) async {
  await startAccountingSession(db, 'stage36-owner');
  await OwnerBootstrapTables.ensure(db);
  for (var i = 0; i < 4; i++) {
    final name = 'عميل تجريبي طويل الاسم لفحص عرض الهاتف $i';
    final id = await ClientService.insertClient(
        Client(name: name, type: 'أفراد', phone: '059912345$i'));
    await SupplierService.insertSupplier(Supplier(
        id: '', pid: '', name: 'مورد مواد دهان وقطع سيارات طويل الاسم $i'));
    await VehicleService.insertVehicle(Vehicle(
        number: '1234567$i', type: 'مرسيدس بنز', model: '2025', clientId: id));
    await db.insert('repairs', {
      'id': 'stage36-$i',
      'client_id': id,
      'receivedDate': DateTime.now().toIso8601String(),
      'beneficiaryName': name,
      'beneficiaryType': 'أفراد',
      'vehicleNumber': '1234567$i',
      'vehicleType': 'مرسيدس بنز',
      'vehicleModel': '2025',
      'repairType': 'إصلاح ودهان كامل للمركبة',
      'fileValue': 123456.78,
      'paidAmount': 0,
      'status': 'APPROVED',
      'vehicleStatus': 'بانتظار الإصلاح'
    });
  }
  final suppliers = await db.query('suppliers', limit: 1);
  await db.insert('purchase_invoices', {
    'id': 'stage36-purchase',
    'supplier_id': suppliers.first['id'],
    'amount_total': 987654.32,
    'paid_total': 0,
    'date': DateTime.now().toIso8601String(),
    'method': 'credit'
  });
  await db.insert('purchase_invoice_lines', {
    'id': 'stage36-line',
    'invoice_id': 'stage36-purchase',
    'item_name': 'مواد دهان وتجهيز للمركبات بوصف طويل لفحص التفاف البنود',
    'qty': 2,
    'unit_price': 493827.16,
    'price': 493827.16,
    'total': 987654.32
  });

  final cash =
      (await db.query('accounts', where: 'code=?', whereArgs: ['1000']))
          .first['id'];
  final bank =
      (await db.query('accounts', where: 'code=?', whereArgs: ['1010']))
          .first['id'];
  await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime.now(),
      source: 'TRANSFER',
      sourceId: 'stage36-transfer',
      createdBy: 'stage36-owner',
      note:
          'حركة اختبار طويلة الوصف لفحص المبلغ والتاريخ والحساب داخل دفتر الأستاذ',
      lines: [
        {'account_id': cash, 'debit': 765432.10, 'credit': 0.0},
        {'account_id': bank, 'debit': 0.0, 'credit': 765432.10}
      ]);
}

Future<void> captureAuditScreen(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('stage36-capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory('.dart_tool/stage36-previews');
    await dir.create(recursive: true);
    await File('${dir.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
}
