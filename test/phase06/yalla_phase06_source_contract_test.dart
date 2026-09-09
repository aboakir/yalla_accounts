import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P06 canonical list route and shell ownership are wired', () {
    final routes = File('lib/core/routes/app_routes.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final shell = File(
      'lib/core/widgets/mobile/yalla_mobile_route_frame.dart',
    ).readAsStringSync();
    final sidebar = File('lib/core/data/sidebar_items.dart').readAsStringSync();

    expect(
      routes,
      contains(
        "if (name == repairsList) {\n"
        "      return _page(settings, const RepairsScreen(showAll: true));",
      ),
    );
    expect(shell, contains('routeName == AppRoutes.repairsList'));
    expect(sidebar, contains("route: AppRoutes.repairsList"));
    expect(sidebar, contains("title: 'ملفات الإصلاح'"));
  });

  test('P06 archive truth is decoupled from payment status', () {
    final db = File(
      'lib/features/repairs/services/repair_database_service.dart',
    ).readAsStringSync();
    final save = File(
      'lib/features/repairs/services/repair_save_service.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/repairs/screens/repairs_screen.dart',
    ).readAsStringSync();

    expect(
      db,
      isNot(contains("isArchived: paymentStatus == 'مسدد'")),
    );
    expect(save, isNot(contains('isArchived: paid >= grandTotal')));
    expect(db, contains('static Future<int> setArchivedOn('));
    expect(db, contains("entityType: 'repair'"));
    expect(screen, contains('repair.isArchived'));
    expect(screen, contains('RepairArchiveScope'));
  });

  test('P06 screen exposes all official list controls', () {
    final filterBar = File(
      'lib/features/repairs/widgets/repair_filter_bar.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/repairs/screens/repairs_screen.dart',
    ).readAsStringSync();

    expect(filterBar, contains("label: 'حالة السداد'"));
    expect(filterBar, contains("label: 'حالة المركبة'"));
    expect(filterBar, contains("label: 'نوع المستفيد'"));
    expect(filterBar, contains("label: 'الأرشيف'"));
    // P13 owns user-facing close/reopen. P06 archive remains an internal
    // persistence primitive and list filter, not a raw UI toggle.
    expect(screen, isNot(contains("'أرشفة الملف'")));
    expect(screen, isNot(contains("'استعادة من الأرشيف'")));
    expect(screen, contains('إعادة فتح الملف المغلق'));
  });
}
