import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  group('Stage 3 release scope', () {
    test('release scope flags defer only the agreed first-beta features', () {
      final text = source('lib/core/release/release_scope_config.dart');
      expect(text, contains('repairReportExportsEnabled = false'));
      expect(text, contains('employeeAdvancesEnabled = false'));
      expect(text, contains('extendedFinanceEnabled = false'));
      expect(text, contains('chequesEnabled = false'));
      expect(text, contains('dashboardFrozen = true'));
    });

    test('sidebar keeps stable finance core and gates deferred modules', () {
      final text = source('lib/core/widgets/sidebar/yalla_sidebar.dart');
      expect(
          text, contains("(Icons.list_alt, 'قيود اليومية', rJournalEntries)"));
      expect(text,
          contains("(Icons.menu_book, 'دفتر الأستاذ', rFinanceAccountLedger)"));
      expect(text, contains('ReleaseScopeConfig.extendedFinanceEnabled'));
      expect(text, contains('ReleaseScopeConfig.employeeAdvancesEnabled'));
      expect(text, contains('ReleaseScopeConfig.chequesEnabled'));
    });

    test('repair reports remain available while export actions are gated', () {
      final text =
          source('lib/features/repairs/screens/repair_reports_screen.dart');
      expect(text, contains("title: const Text('📊 تقارير الإصلاح'"));
      expect(text, contains('ReleaseScopeConfig.repairReportExportsEnabled'));
      expect(text, contains('exportRepairsToPdf'));
      expect(text, contains('exportRepairsToExcel'));
    });

    test(
        'direct advances/rewards UI is gated and payment voucher remains canonical',
        () {
      final details =
          source('lib/features/employees/screens/employee_details_screen.dart');
      final voucher =
          source('lib/features/vouchers/screens/payment_voucher_screen.dart');
      expect(details, contains('ReleaseScopeConfig.employeeAdvancesEnabled'));
      expect(voucher, contains('DropdownMenuItem(value: "موظف"'));
      expect(voucher,
          contains('source: expenseType == "موظف" ? "EMP_ADV" : null'));
      expect(voucher,
          contains('sourceId: expenseType == "موظف" ? partyId : null'));
    });

    test('supplier cheque entry points are gated without deleting cheque code',
        () {
      final suppliers =
          source('lib/features/suppliers/screens/suppliers_screen.dart');
      final account =
          source('lib/features/suppliers/screens/supplier_account_screen.dart');
      expect(suppliers, contains('ReleaseScopeConfig.chequesEnabled'));
      expect(account, contains('ReleaseScopeConfig.chequesEnabled'));
      expect(suppliers, contains("'/suppliers/cheques'"));
      expect(account, contains('AppRoutes.supplierCheques'));
    });
  });
}
