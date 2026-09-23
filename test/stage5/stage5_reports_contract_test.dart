import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('Stage 5 reports/search permanent contracts', () {
    test('repair reports use canonical paid truth and exports are enabled', () {
      final scope = read('lib/core/release/release_scope_config.dart');
      final provider = read(
        'lib/features/repairs/providers/repair_reports_provider.dart',
      );
      final screen = read(
        'lib/features/repairs/screens/repair_reports_screen.dart',
      );

      expect(scope, contains('repairReportExportsEnabled = true'));
      expect(provider, contains('RepairFinancialTruthService.paidByRepairSql'));
      expect(screen, contains('ref.watch(repairReportsProvider)'));
      expect(screen, isNot(contains('ref.watch(repairsProvider)')));
    });

    test('global search covers required entities and restores focus', () {
      final service = read('lib/core/services/global_search_service.dart');
      final screen = read(
        'lib/features/search/screens/global_search_screen.dart',
      );

      for (final token in [
        '_searchVehicles',
        '_searchPolicyDocuments',
        '_searchRawMaterials',
        "source: 'vehicles'",
        "source: 'documents'",
        "source: 'items'",
      ]) {
        expect(service, contains(token), reason: 'missing $token');
      }
      expect(screen, contains("case 'vehicles':"));
      expect(screen, contains("case 'documents':"));
      expect(screen, contains("case 'items':"));
      final awaitedNavigation = screen.indexOf('await AppRoutes.pushNamedSafe');
      final focusRestore = screen.lastIndexOf('_focus.requestFocus()');
      expect(awaitedNavigation, greaterThanOrEqualTo(0));
      expect(focusRestore, greaterThan(awaitedNavigation));
    });

    test('reports hub exposes all Stage 5 module reports', () {
      final hub = read(
        'lib/features/reports/screens/reports_dashboard_screen.dart',
      );
      for (final route in [
        'AppRoutes.purchasesSuppliersAging',
        'AppRoutes.rawMaterials',
        'AppRoutes.chequesReport',
        'AppRoutes.insuranceAgentReports',
      ]) {
        expect(hub, contains(route), reason: 'missing $route');
        expect(RegExp(RegExp.escape(route)).allMatches(hub), hasLength(1),
            reason: 'duplicate $route card');
      }
    });

    test('GL reports use half-open whole-day boundaries', () {
      final gl = read('lib/core/services/reports_gl_service.dart');
      expect(gl, contains('DateTime(value.year, value.month, value.day)'));
      expect(gl, contains('add(const Duration(days: 1))'));
      expect(gl, contains('e.date < ?'));
    });
  });
}
