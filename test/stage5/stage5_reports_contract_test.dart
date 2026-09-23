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
        'AppRoutes.inventory',
        'AppRoutes.chequesReport',
        'AppRoutes.insuranceAgentReports',
      ]) {
        expect(hub, contains(route), reason: 'missing $route');
        expect(RegExp(RegExp.escape(route)).allMatches(hub), hasLength(1),
            reason: 'duplicate $route card');
      }
    });

    test('inventory report is canonical and exportable after Stage 4 merge',
        () {
      final hub = read(
        'lib/features/reports/screens/reports_dashboard_screen.dart',
      );
      final inventory = read(
        'lib/features/inventory/screens/inventory_list_screen.dart',
      );

      expect(hub, contains('AppRoutes.inventory'));
      expect(hub, isNot(contains('PENDING_STAGE4_MERGE')));
      expect(inventory, contains('InventoryOperationsService.valuation'));
      expect(inventory, contains('InventoryOperationsService.reorderStatus'));
      expect(inventory, contains('Future<void> _exportCsv()'));
      expect(inventory, contains('Future<void> _exportPdf()'));
      expect(inventory, contains('YallaPdfService.generateTablePdf'));
      expect(inventory, contains('Printing.layoutPdf'));
      expect(inventory, contains('inventory-report-search'));
      expect(inventory, contains('_visibleStockValue'));
    });

    test('aging reports use canonical party GL truth', () {
      final ar = read('lib/features/reports/providers/ar_aging_provider.dart');
      final apScreen = read(
        'lib/features/finance/purchases/screens/suppliers_aging_screen.dart',
      );
      expect(ar, contains('v_party_gl_lines'));
      expect(apScreen, contains('SupplierAgingProvider.fetch'));
      expect(apScreen, isNot(contains('FROM gl_lines l')));
    });

    test('balance sheet exports visible GL totals to CSV and printable PDF',
        () {
      final screen = read(
        'lib/features/finance/reports/screens/balance_sheet_screen.dart',
      );
      expect(screen, contains('Future<void> _exportCsv()'));
      expect(screen, contains('Future<void> _exportPdf()'));
      expect(screen, contains('Share.shareXFiles'));
      expect(screen, contains('Printing.layoutPdf'));
      expect(screen, contains('_assets'));
      expect(screen, contains('_liabilities'));
      expect(screen, contains('_equity'));
    });

    test('trial balance exports visible GL rows to CSV and printable PDF', () {
      final screen = read(
        'lib/features/reports/screens/trial_balance_screen.dart',
      );
      expect(screen, contains('Future<void> _exportCsv()'));
      expect(screen, contains('Future<void> _exportPdf()'));
      expect(screen, contains('Share.shareXFiles'));
      expect(screen, contains('Printing.layoutPdf'));
      expect(screen, contains('_rows'));
      expect(screen, contains('_sumDebit'));
      expect(screen, contains('_sumCredit'));
    });

    test('GL reports use half-open whole-day boundaries', () {
      final gl = read('lib/core/services/reports_gl_service.dart');
      expect(gl, contains('DateTime(value.year, value.month, value.day)'));
      expect(gl, contains('add(const Duration(days: 1))'));
      expect(gl, contains('e.date < ?'));
    });
  });
}
