import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    double width,
    Widget child,
  ) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in <double>[320, 375, 430, 600, 768, 1024, 1440]) {
    testWidgets('Toolbar spacer remains valid at width $width', (tester) async {
      await pumpAt(
          tester,
          width,
          AdaptiveRow(children: [
            const Text('التقرير'),
            const Spacer(),
            OutlinedButton(
                onPressed: () {}, child: const Text('تصدير التقرير')),
            OutlinedButton(
                onPressed: () {}, child: const Text('تحديث النتائج')),
          ]));
      expect(tester.takeException(), isNull);
      expect(find.text('تصدير التقرير'), findsOneWidget);
      expect(find.text('تحديث النتائج'), findsOneWidget);
    });

    testWidgets('AdaptiveRow stays usable at width $width', (tester) async {
      await pumpAt(
        tester,
        width,
        const Padding(
          padding: EdgeInsets.all(12),
          child: AdaptiveRow(
            children: [
              Expanded(
                child: TextField(
                  key: Key('a'),
                  decoration: InputDecoration(labelText: 'الحقل الأول'),
                ),
              ),
              SizedBox(width: 18),
              Expanded(
                child: TextField(
                  key: Key('b'),
                  decoration: InputDecoration(labelText: 'الحقل الثاني'),
                ),
              ),
            ],
          ),
        ),
      );

      final a = tester.getRect(find.byKey(const Key('a')));
      final b = tester.getRect(find.byKey(const Key('b')));
      if (width < YallaBreakpoints.denseRowStack) {
        expect(b.top, greaterThan(a.top));
        expect(a.width, greaterThan(width - 80));
      } else {
        expect((a.top - b.top).abs(), lessThan(1));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('AdaptiveDataTable renders a phone-safe card view at 320px',
      (tester) async {
    await pumpAt(
      tester,
      320,
      const AdaptiveDataTable(
        columns: [
          DataColumn(label: Text('رقم الملف الطويل')),
          DataColumn(label: Text('اسم العميل الكامل')),
          DataColumn(label: Text('القيمة المستحقة')),
          DataColumn(label: Text('الحالة الحالية')),
        ],
        rows: [
          DataRow(
            cells: [
              DataCell(Text('123456789')),
              DataCell(Text('عميل تجريبي طويل الاسم')),
              DataCell(Text('12,345.67')),
              DataCell(Text('قيد التحصيل')),
            ],
          ),
        ],
      ),
    );

    // Phone intentionally becomes a card/list experience rather than a
    // squeezed or horizontally-scrolled desktop DataTable.
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('رقم الملف الطويل'), findsOneWidget);
    expect(find.text('123456789'), findsOneWidget);
    expect(find.text('عميل تجريبي طويل الاسم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AdaptiveAlertDialog fits a 320px phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AdaptiveAlertDialog(
                    title: Text('اختبار'),
                    content: SizedBox(
                      width: 700,
                      child: Text('محتوى حوار عريض يجب ألا يخرج عن الهاتف'),
                    ),
                  ),
                ),
                child: const Text('فتح'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('اختبار'), findsOneWidget);
  });

  test('desktop-prone tables/dialogs use adaptive wrappers', () {
    final rawTable = RegExp(
      r'(^|[^A-Za-z0-9_.])DataTable\s*\(',
      multiLine: true,
    );
    final rawDialog = RegExp(
      r'(^|[^A-Za-z0-9_.])AlertDialog\s*\(',
      multiLine: true,
    );
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.endsWith('lib/shared/widgets/adaptive_layout.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (rawTable.hasMatch(source) || rawDialog.hasMatch(source)) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Raw DataTable/AlertDialog escaped the adaptive layer. Compact Row widgets are allowed.',
    );
  });

  test('responsive breakpoints are unified at 600 / 1024', () {
    final builder = File(
      'lib/shared/layouts/responsive_builder.dart',
    ).readAsStringSync();
    final canonical = File(
      'lib/core/design/yalla_breakpoints.dart',
    ).readAsStringSync();
    final legacy = File(
      'lib/shared/widgets/responsive.dart',
    ).readAsStringSync();
    final scaffold = File(
      'lib/shared/widgets/responsive_scaffold.dart',
    ).readAsStringSync();

    expect(canonical, contains('static const double tablet = 600'));
    expect(canonical, contains('static const double desktop = 1024'));
    expect(
      builder,
      contains('this.tablet = design.YallaBreakpoints.tablet'),
      reason: 'ResponsiveBuilder must consume the canonical tablet breakpoint.',
    );
    expect(
      builder,
      contains('this.desktop = design.YallaBreakpoints.desktop'),
      reason:
          'ResponsiveBuilder must consume the canonical desktop breakpoint.',
    );
    expect(legacy, contains('mobileMaxWidth = YallaBreakpoints.tablet'));
    expect(legacy, contains('tabletMinWidth = YallaBreakpoints.tablet'));
    expect(legacy, contains('desktopMinWidth = YallaBreakpoints.desktop'));
    expect(
      scaffold,
      contains('this.breakpoint = design.YallaBreakpoints.desktop'),
      reason:
          'ResponsiveScaffold must consume the canonical desktop breakpoint.',
    );
  });

  test('known dashboard grids include a one-column phone mode', () {
    final employees = File(
      'lib/features/employees/screens/employee_dashboard_screen.dart',
    ).readAsStringSync();
    final cheques = File(
      'lib/features/cheques/screens/cheques_dashboard_screen.dart',
    ).readAsStringSync();
    final quickActions = File(
      'lib/shared/widgets/dashboard/quick_actions.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'w\s*>=\s*600').hasMatch(employees),
      isTrue,
      reason: 'Employee dashboard must switch at the phone/tablet breakpoint.',
    );
    expect(
      RegExp(r':\s*1\s*;').hasMatch(employees),
      isTrue,
      reason: 'Employee dashboard must include a one-column phone branch.',
    );
    expect(
      RegExp(
        r'viewportWidth\s*>=\s*600\s*\?\s*2\s*:\s*1',
        multiLine: true,
      ).hasMatch(cheques),
      isTrue,
      reason:
          'Cheque dashboard must preserve the 2-column tablet / 1-column phone branch after dart format.',
    );
    expect(
      RegExp(r'DeviceType\.mobile\s*=>\s*1').hasMatch(quickActions),
      isTrue,
      reason: 'Quick actions must use one column on mobile.',
    );
  });

  test('mobile navigation remains reachable on phone and tablet', () {
    final dashboard = File(
      'lib/features/home/screens/dashboard_screen.dart',
    ).readAsStringSync();
    final appBar = File(
      'lib/core/widgets/yalla_appbar.dart',
    ).readAsStringSync();
    final sidebar = File(
      'lib/core/widgets/sidebar/yalla_sidebar.dart',
    ).readAsStringSync();
    final sidebarHeader = File(
      'lib/core/widgets/sidebar/sidebar_header.dart',
    ).readAsStringSync();
    final yallaScaffold = File(
      'lib/core/widgets/yalla_scaffold.dart',
    ).readAsStringSync();
    final responsiveScaffold = File(
      'lib/shared/widgets/responsive_scaffold.dart',
    ).readAsStringSync();

    expect(
      dashboard,
      contains("Key('yalla_mobile_menu_button')"),
      reason: 'Dashboard must expose a visible phone/tablet menu button.',
    );
    expect(
      dashboard,
      contains('Scaffold.of(headerContext).openDrawer()'),
      reason: 'Dashboard menu button must actually open the drawer.',
    );
    expect(
      dashboard,
      contains('body: SafeArea('),
      reason: 'Dashboard content/header must stay below the iOS status bar.',
    );

    expect(
      RegExp(r'scaffold\.widget\.drawer\s*!=\s*null').hasMatch(appBar),
      isTrue,
    );
    expect(
      RegExp(r'scaffold\.widget\.endDrawer\s*!=\s*null').hasMatch(appBar),
      isTrue,
    );
    expect(
      RegExp(r'scaffold\s*\.\s*openDrawer\s*\(\s*\)').hasMatch(appBar),
      isTrue,
    );
    expect(
      RegExp(r'scaffold\s*\.\s*openEndDrawer\s*\(\s*\)').hasMatch(appBar),
      isTrue,
    );

    expect(
      RegExp(
        r'scaffoldState\?\s*\.\s*isEndDrawerOpen\s*==\s*true',
        multiLine: true,
      ).hasMatch(sidebar),
      isTrue,
      reason: 'Sidebar must detect and close an open endDrawer too.',
    );
    expect(
      RegExp(
        r'targetNavigator\s*\.\s*pushNamedAndRemoveUntil\s*\(',
        multiLine: true,
      ).hasMatch(sidebar),
      isTrue,
      reason:
          'Compact navigation must replace the unstable drawer route stack.',
    );
    expect(
      RegExp(
        r'targetNavigator\s*\.\s*pushReplacementNamed\s*\(\s*route\s*\)',
        multiLine: true,
      ).hasMatch(sidebar),
      isTrue,
      reason: 'Desktop navigation must preserve direct route replacement.',
    );
    expect(
      RegExp(r'context\.isDesktopWidth\s*\?').hasMatch(sidebar),
      isTrue,
    );
    expect(
      sidebarHeader,
      contains('if (widget.showToggle)'),
      reason: 'Mobile drawer must not expose the desktop collapse control.',
    );

    expect(
      RegExp(r'drawer\s*:\s*!isDesktop').hasMatch(yallaScaffold),
      isTrue,
      reason: 'Tablet widths below 1024 must retain drawer navigation.',
    );
    expect(
      RegExp(r'drawer\s*:\s*!isWide').hasMatch(responsiveScaffold),
      isTrue,
      reason: 'ResponsiveScaffold compact navigation must use a real drawer.',
    );
    expect(
      RegExp(r'endDrawer\s*:\s*!isWide').hasMatch(responsiveScaffold),
      isFalse,
      reason: 'Do not split compact navigation between drawer conventions.',
    );
  });
}
