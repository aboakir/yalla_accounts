import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  group('Stage 3 release scope', () {
    test('release scope exposes the approved operational modules', () {
      final text = source('lib/core/release/release_scope_config.dart');
      expect(text, contains('repairReportExportsEnabled = false'));
      expect(text, contains('employeeAdvancesEnabled = true'));
      expect(text, contains('extendedFinanceEnabled = true'));
      expect(text, contains('chequesEnabled = true'));
      expect(text, contains('dashboardFrozen = true'));
    });

    test('sidebar exposes operational modules without a deferred placeholder',
        () {
      final text = source('lib/core/widgets/sidebar/yalla_sidebar.dart');
      expect(
          text, contains("(Icons.list_alt, 'قيود اليومية', rJournalEntries)"));
      expect(text,
          contains("(Icons.menu_book, 'دفتر الأستاذ', rFinanceAccountLedger)"));
      expect(text, contains("'اللوحة المالية'"));
      expect(text, contains("'المصروفات'"));
      expect(text, contains("'تقرير السلف والمكافآت'"));
      expect(text, contains("'شيكات آجلة'"));
      expect(text, contains("'مشتريات مواد الدهان'"));
      expect(text, contains("'مشتريات العِدّة والأدوات'"));
      expect(text, contains("'المخزون والمواد'"));
      expect(text, isNot(contains("title: 'إصدار لاحق'")));
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
      expect(voucher, contains("'PAYROLL_ENTITLEMENT'"));
      expect(voucher, contains("'EMPLOYEE_BONUS'"));
      expect(voucher, contains("'EMP_ADV'"));
      expect(voucher, contains("sourceId: expenseType == 'موظف'"));
    });

    test('supplier cheque entry points are gated without deleting cheque code',
        () {
      final suppliers =
          source('lib/features/suppliers/screens/suppliers_screen.dart');
      final account =
          source('lib/features/suppliers/screens/supplier_account_screen.dart');
      expect(suppliers, contains('ReleaseScopeConfig.chequesEnabled'));
      expect(suppliers, contains("'/suppliers/cheques'"));
      expect(account, isNot(contains('AppRoutes.supplierCheques')));
      expect(account, isNot(contains("'/suppliers/cheques'")));
    });
  });
}
