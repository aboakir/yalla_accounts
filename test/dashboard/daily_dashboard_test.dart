import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/home/services/daily_dashboard_service.dart';
import 'package:yalla_accounts/features/home/widgets/daily_dashboard_content.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  late Database db;
  dynamic session;
  late DailyDashboardData empty;
  final now = DateTime(2026, 9, 9, 12);
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('dashboard_');
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    session = null;
    empty = await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
  });
  tearDown(() async {
    if (session != null) {
      await session.endEphemeralPreviewSession();
    }
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> accountId(String parentCode) async {
    final code = '$parentCode.RFC';
    final rows = await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isNotEmpty) return (rows.single['id'] as num).toInt();
    final isRevenue = parentCode == '4000';
    return db.insert('accounts', {
      'code': code,
      'name': 'RFC posting $parentCode',
      'type': isRevenue ? 'REVENUE' : 'ASSET',
      'normal_balance': isRevenue ? 'CREDIT' : 'DEBIT',
    });
  }

  Future<void> seedCollectionRepair({
    required String id,
    double amount = 6800,
    double paid = 0,
    bool financiallyPosted = false,
    String status = 'APPROVED',
    String vehicleStatus = 'قيد الإصلاح',
  }) async {
    await db.insert('repairs', {
      'id': id,
      'receivedDate': '2026-09-01',
      'fileValue': amount,
      'paidAmount': 999999,
      'total_paid_amount': 999999,
      'vehicleStatus': vehicleStatus,
      'beneficiaryName': 'عميل $id',
      'status': status,
    });
    if (!financiallyPosted) return;
    session ??= await startAccountingSession(db, 'dashboard-rfc-$id');

    final invoiceId = 'INV-$id';
    await db.insert('invoices', {
      'id': invoiceId,
      'repair_id': id,
      'date': '2026-09-01',
      'total': amount,
      'status': 'UNPAID',
      'created_at': '2026-09-01T10:00:00',
    });
    final ar = await accountId('1200');
    final revenue = await accountId('4000');
    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 9, 1),
      source: 'INVOICE',
      sourceId: invoiceId,
      lines: [
        {
          'account_id': ar,
          'debit': amount,
          'credit': 0.0,
          'repair_id': id,
          'invoice_id': invoiceId
        },
        {
          'account_id': revenue,
          'debit': 0.0,
          'credit': amount,
          'repair_id': id,
          'invoice_id': invoiceId
        },
      ],
    );
    if (paid <= 0) return;
    final cash = await accountId('1000');
    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 9, 2),
      source: 'PAYMENT',
      sourceId: 'PAY-$id',
      lines: [
        {
          'account_id': cash,
          'debit': paid,
          'credit': 0.0,
          'repair_id': id,
          'invoice_id': invoiceId
        },
        {
          'account_id': ar,
          'debit': 0.0,
          'credit': paid,
          'repair_id': id,
          'invoice_id': invoiceId
        },
      ],
    );
  }

  test(
      'empty database produces exactly three actionable fallbacks without writes',
      () async {
    final before = await db.rawQuery('SELECT COUNT(*) n FROM gl_entries');
    for (final period in DashboardPeriod.values) {
      final data = await DailyDashboardService.loadOn(db, period, now);
      expect(data.today.receipts, 0);
      expect(data.readyAmount, 0);
      expect(DailyDashboardService.recommendations(data, period), hasLength(3));
    }
    expect(await db.rawQuery('SELECT COUNT(*) n FROM gl_entries'), before);
  });
  test('RFC-001 delivered without financial finalization is not collectible',
      () async {
    await seedCollectionRepair(
      id: 'delivered-unfinalized',
      vehicleStatus: 'تم التسليم',
    );
    final data =
        await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
    expect(data.readyAmount, 0);
    expect(data.collectionItems, isEmpty);
  });

  test('RFC-002 financially posted outstanding repair is collectible',
      () async {
    await seedCollectionRepair(id: 'approved', financiallyPosted: true);
    final data =
        await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
    expect(data.readyAmount, 6800);
    expect(data.collectionItems, hasLength(1));
    expect(data.collectionItems.single.repairId, 'approved');
    expect(data.cars.single.stage, isNot('جاهز للتسليم'));
  });

  test('RFC-003 fully paid repair is not collectible', () async {
    await seedCollectionRepair(
        id: 'fully-paid', financiallyPosted: true, paid: 6800);
    final data =
        await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
    expect(data.readyAmount, 0);
    expect(data.collectionItems, isEmpty);
  });

  test('RFC-004 cancelled obligation is not collectible', () async {
    await seedCollectionRepair(
      id: 'cancelled',
      financiallyPosted: true,
      status: 'CANCELLED',
    );
    final data =
        await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
    expect(data.readyAmount, 0);
    expect(data.collectionItems, isEmpty);
  });

  test('RFC-005 dashboard total equals eligible detail rows exactly', () async {
    await seedCollectionRepair(
        id: 'one', financiallyPosted: true, amount: 6800);
    await seedCollectionRepair(
        id: 'two', financiallyPosted: true, amount: 3200);
    final data =
        await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
    expect(data.collectionItems, hasLength(2));
    expect(data.readyAmount, 10000);
    expect(data.collectionItems.fold<double>(0, (n, item) => n + item.amount),
        data.readyAmount);
  });

  testWidgets('RFC-006 collection details explain dashboard total exactly',
      (tester) async {
    final data = DailyDashboardData(
      name: empty.name,
      logo: empty.logo,
      currency: empty.currency,
      today: empty.today,
      period: empty.period,
      cars: const [],
      collectionItems: const [
        DashboardCollectionItem(
          repairId: 'one',
          name: 'عميل one',
          amount: 6800,
          invoiceId: 'INV-one',
        ),
        DashboardCollectionItem(
          repairId: 'two',
          name: 'عميل two',
          amount: 3200,
          invoiceId: 'INV-two',
        ),
      ],
      newFiles: 0,
      previousFiles: 0,
      materials: const [],
      issues: const [],
      now: now,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardCollectionDetailsDialog(
          data: data,
          onOpen: (_, __) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('تفاصيل الجاهز للتحصيل'), findsOneWidget);
    expect(find.text('عميل one'), findsOneWidget);
    expect(find.text('عميل two'), findsOneWidget);
    expect(find.text('فاتورة INV-one'), findsOneWidget);
    expect(find.text('فاتورة INV-two'), findsOneWidget);
    expect(find.text('الإجمالي'), findsOneWidget);
    expect(find.text(data.money(data.readyAmount)), findsOneWidget);
  });
  test(
      'calendar boundaries and equal elapsed comparison exclude future records',
      () async {
    for (final date in ['2026-09-08', '2026-09-09', '2026-09-10']) {
      await db.insert('repairs', {'id': date, 'receivedDate': date});
    }
    final data =
        await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
    expect(data.newFiles, 1);
    expect(data.recentFiles.map((r) => r['id']).toList(),
        ['2026-09-09', '2026-09-08']);
    expect(data.previousFiles, 1);
    expect(DashboardPeriod.week.start(now), DateTime(2026, 9, 6));
    expect(DashboardPeriod.month.start(now), DateTime(2026, 9, 1));
  });
  testWidgets('Arabic font preview at iPhone 15 Pro Max size', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = FontLoader('DashboardArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    await fonts.load();
    await (FontLoader('DashboardSymbols')
          ..addFont(rootBundle.load('assets/fonts/Tahoma-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            fontFamily: 'DashboardArabic',
            fontFamilyFallback: const ['DashboardSymbols'],
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xfff5f7f5),
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xff68bb10))),
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(
                key: const ValueKey('preview'),
                child: Scaffold(
                    appBar: AppBar(
                        title: const Text('ورشتي'),
                        leading: const Icon(Icons.menu)),
                    body: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: DailyDashboardContent(
                                data: empty,
                                period: DashboardPeriod.today,
                                onPeriod: (_) {},
                                onOpen: (_, __) {},
                                onEntry: () {}))))))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('preview')));
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('.dart_tool/dashboard-iphone-preview.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [430.0, 320.0]) {
    testWidgets(
        'Arabic content has no overflow at width $width and enlarged text',
        (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = Size(width, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 932),
                  textScaler: const TextScaler.linear(1.5)),
              child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                      body: SingleChildScrollView(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: DailyDashboardContent(
                                  data: empty,
                                  period: DashboardPeriod.today,
                                  onPeriod: (_) {},
                                  onOpen: (_, __) {},
                                  onEntry: () {}))))))));
      await tester.pump();
      expect(Directionality.of(tester.element(find.text('المساعد الذكي'))),
          TextDirection.rtl);
      expect(tester.takeException(), isNull);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -1800));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('steps stay stable and navigate manually without auto rotation',
      (tester) async {
    DashboardPeriod? selected;
    String? route;
    final steps =
        DailyDashboardService.recommendations(empty, DashboardPeriod.today);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BestStepCard(
                steps: steps,
                period: DashboardPeriod.today,
                onPeriod: (p) => selected = p,
                onOpen: (r, id) => route = r))));
    expect(find.text(steps[0].title), findsOneWidget);
    expect(find.text(steps[0].impact), findsNothing);
    await tester.tap(find.text(steps[0].title));
    await tester.pumpAndSettle();
    expect(find.text(steps[0].impact), findsOneWidget);
    Navigator.of(tester.element(find.text(steps[0].impact))).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(steps[0].title), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('الخطوة 3 من 3'));
    await tester.pump();
    expect(find.text(steps[2].title), findsOneWidget);
    await tester.tap(find.text(steps[2].action));
    expect(route, steps[2].route);
    expect(selected, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
