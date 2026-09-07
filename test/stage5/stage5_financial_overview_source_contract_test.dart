import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Stage 5 overview service reads GL and Party views only', () {
    final source = File(
      'lib/features/finance/services/financial_overview_service.dart',
    ).readAsStringSync();

    expect(source, contains('gl_entries'));
    expect(source, contains('gl_lines'));
    expect(source, contains('accounts'));
    expect(source, contains('v_party_gl_lines'));
    expect(source, contains("a.code='2140' OR a.code LIKE '2140.%'"));
    expect(source, contains('AccountingIntegrityService.healthReportOn'));

    // No parallel financial truth from operational/legacy totals.
    expect(source, isNot(contains('FROM invoices')));
    expect(source, isNot(contains('FROM purchase_invoices')));
    expect(source, isNot(contains('FROM salaries')));
    expect(source, isNot(contains('FROM monthly_expenses')));
    expect(source, isNot(contains('ledger_entries')));
  });

  test('Stage 5 finance dashboard delegates calculations to overview service',
      () {
    final source = File(
      'lib/features/finance/screens/finance_dashboard_screen.dart',
    ).readAsStringSync();

    expect(source, contains('FinancialOverviewService.load('));
    expect(source, contains('صافي ربح الفترة'));
    expect(source, contains('السلامة المحاسبية'));
    expect(source, contains('ذمم العملاء'));
    expect(source, contains('ذمم الموردين'));
    expect(source, contains('رواتب مستحقة'));
    expect(source, isNot(contains('DBService.database')));
    expect(source, isNot(contains('_sumDebit - _sumCredit')));
    expect(source, isNot(contains('entryId')));
  });
}
