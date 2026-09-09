import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('P03 phone shell exposes the current approved daily destinations', () {
    final nav = read(
      'lib/core/widgets/mobile/yalla_mobile_bottom_nav.dart',
    );

    for (final label in <String>[
      'الرئيسية',
      'الإصلاحات',
      'إضافة',
      'المزيد',
    ]) {
      expect(nav, contains("label: '$label'"));
    }

    expect(nav, contains('AppRoutes.dashboard'));
    expect(nav, contains('AppRoutes.repairsDashboard'));
    expect(nav, contains('AppRoutes.repairsAdd'));
    expect(nav, contains('onMore();'));
    expect(nav, contains('const YallaSyncStatusStrip()'));
  });

  test('P03 home is a decision-first Today screen, not the old KPI wall', () {
    final dashboard = read(
      'lib/features/home/screens/dashboard_screen.dart',
    );

    expect(dashboard, contains("Key('yalla_mobile_menu_button')"));
    expect(dashboard, contains('Scaffold.of(headerContext).openDrawer()'));

    final content =
        read('lib/features/home/widgets/daily_dashboard_content.dart');
    expect(content, contains("'صافي اليوم'"));
    expect(content, contains("'أفضل خطوة'"));
    expect(content, contains("'يحتاج انتباهك'"));
    expect(content, contains("'إجراءات سريعة'"));
    expect(content, contains("'آخر حركة موثقة'"));
    expect(dashboard, contains('DailyDashboardService.load('));
    expect(dashboard, isNot(contains("'جاهزة للتسليم'")));
    expect(dashboard, isNot(contains('_recentRepairPlaceholder')));
  });

  test('P03 home summary reads existing source-of-truth tables only', () {
    final service = read(
      'lib/features/home/services/p03_home_service.dart',
    );

    expect(service, contains('FROM repairs'));
    expect(service, contains('FinancialOverviewService.cashFlowsOn'));
    expect(service, contains('FROM cheques'));
    expect(service, contains('WorkshopSettingsService.instance.getSettings()'));
    expect(service, contains('CommercialSettingsService.instance.get()'));
    expect(service, contains("COALESCE(paymentStatus, '') <> 'مسدد'"));
    expect(service, isNot(contains('INSERT INTO')));
    expect(service, isNot(contains('UPDATE ')));
    expect(service, isNot(contains('ALTER TABLE')));
    expect(service, isNot(contains('CREATE TABLE')));
  });

  test('P03 dashboard keeps adaptive responsive primitives', () {
    final dashboard = read(
      'lib/features/home/screens/dashboard_screen.dart',
    );

    expect(dashboard, contains('TextDirection.rtl'));
    expect(dashboard, contains('ConstrainedBox('));
    expect(dashboard, contains('ListView('));
  });

  test('C01 iPhone fixes keep sidebar Arabic and Home dates presentation-safe',
      () {
    final sidebar = read(
      'lib/core/widgets/sidebar/yalla_sidebar.dart',
    );
    final homeService = read(
      'lib/features/home/services/p03_home_service.dart',
    );
    final repairs = read(
      'lib/features/repairs/screens/repairs_screen.dart',
    );

    for (final label in <String>[
      'لوحة التحكم',
      'إصلاح المركبات',
      'العملاء والموردون',
      'المالية',
      'الشيكات',
      'الإعدادات',
    ]) {
      expect(sidebar, contains(label));
    }

    for (final bad in <String>['ط§', 'ظ„', 'ط¥', 'ًں', 'â€”']) {
      expect(sidebar, isNot(contains(bad)));
    }

    expect(homeService, contains('static String _displayDate(Object? value)'));
    expect(homeService,
        contains("final received = _displayDate(row['receivedDate']);"));
    expect(
        homeService,
        contains(
            "final due = _displayDate(_firstText(row, const ['due_date', 'date']));"));
    expect(repairs, isNot(contains('آ·')));
  });
}
