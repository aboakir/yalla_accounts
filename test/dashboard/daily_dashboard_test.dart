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
import 'package:yalla_accounts/features/home/services/daily_dashboard_service.dart';
import 'package:yalla_accounts/features/home/widgets/daily_dashboard_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  late Database db;
  late DailyDashboardData empty;
  final now = DateTime(2026, 9, 9, 12);
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('dashboard_');
    db = await DatabaseMigration.initDatabase(
        pathOverride: '${dir.path}/test.db');
    empty = await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
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
  test('ready balances ignore paid cache, cancelled and delivered files',
      () async {
    for (final id in ['ready', 'cancelled', 'delivered']) {
      await db.insert('repairs', {
        'id': id,
        'receivedDate': '2026-09-01',
        'fileValue': 6800,
        'paidAmount': 6800,
        'vehicleStatus': id == 'delivered' ? 'تم التسليم' : 'جاهزة للتسليم',
        'status': id == 'cancelled' ? 'CANCELLED' : 'APPROVED'
      });
    }
    final data =
        await DailyDashboardService.loadOn(db, DashboardPeriod.today, now);
    expect(data.cars, hasLength(1));
    expect(data.recentFiles.map((r) => r['id']),
        containsAll(['ready', 'delivered']));
    expect(data.recentFiles.map((r) => r['id']), isNot(contains('cancelled')));
    expect(data.readyAmount, 6800);
    final steps =
        DailyDashboardService.recommendations(data, DashboardPeriod.today);
    expect(steps.first.id, 'collect');
    expect(steps.first.repairId, 'ready');
    expect(steps, hasLength(3));
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
      expect(Directionality.of(tester.element(find.text('أفضل خطوة'))),
          TextDirection.rtl);
      expect(tester.takeException(), isNull);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -1800));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'steps rotate, navigate manually, select period and dispose timer',
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
    expect(find.text(steps[1].title), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('الخطوة 3 من 3'));
    await tester.pump();
    expect(find.text(steps[2].title), findsOneWidget);
    await tester.tap(find.text(steps[2].action));
    expect(route, steps[2].route);
    await tester.tap(find.text('الشهر'));
    expect(selected, DashboardPeriod.month);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
