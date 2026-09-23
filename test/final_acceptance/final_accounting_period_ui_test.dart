import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/finance/screens/accounting_periods_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final seededPeriods = <Map<String, Object?>>[
    {
      'id': 1,
      'period_start_utc': DateTime(2026, 9, 1).toUtc().toIso8601String(),
      'period_end_exclusive_utc':
          DateTime(2026, 10, 1).toUtc().toIso8601String(),
      'status': 'CLOSED',
      'closed_at': DateTime(2026, 10, 1).toUtc().toIso8601String(),
      'closed_by': 'ui-owner',
      'note': 'UI acceptance seed',
    },
  ];

  for (final size in <Size>[
    const Size(320, 700),
    const Size(1280, 800),
  ]) {
    testWidgets('accounting periods UI fits $size and exposes close history',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AccountingPeriodsScreen(
              loadPeriods: () async => seededPeriods,
              closePeriod: (start, end, note) async {},
              reopenPeriod: (closeId, reason) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('الفترات المحاسبية'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('accounting-period-close-button')),
        findsOneWidget,
      );
      expect(find.text('إعادة فتح'), findsOneWidget);
      expect(find.textContaining('UI acceptance seed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('accounting periods route is wired into finance navigation', () {
    expect(AppRoutes.accountingPeriods, '/finance/accounting-periods');
    final routeSource =
        File('lib/core/routes/app_routes.dart').readAsStringSync();
    final sidebarSource =
        File('lib/core/widgets/sidebar/yalla_sidebar.dart').readAsStringSync();

    expect(routeSource, contains('const AccountingPeriodsScreen()'));
    expect(sidebarSource, contains('الفترات المحاسبية'));
    expect(sidebarSource, contains('AppRoutes.accountingPeriods'));
  });
}
