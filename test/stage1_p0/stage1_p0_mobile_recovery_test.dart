import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P0-01 phone repair details use stable mobile recovery body', () {
    final source = File(
      'lib/features/repairs/screens/repair_details_screen.dart',
    ).readAsStringSync();

    expect(source, contains('STAGE1_P0_01_FINAL_FIX4C_PHONE_PARITY'));
    expect(source, contains('Widget _buildPhoneDetailsParity({'));
    expect(source, contains('_repair.displayPaymentStatus'));
    expect(source, contains(r"Text('حالة المركبة: $vehicleStatus')"));
    expect(source, contains("_buildDataTable('أعمال الإصلاح'"));
    expect(source, contains("_buildDataTable('القطع المطلوبة'"));
    expect(source, contains('if (width < YallaBreakpoints.phone)'));
    expect(source, contains('return _buildPhoneDetailsParity('));
  });

  test('P0-02 repair journal uses canonical route and repair SQL scope', () {
    final repairs = File(
      'lib/features/repairs/screens/repairs_screen.dart',
    ).readAsStringSync();
    final routes = File(
      'lib/core/routes/app_routes.dart',
    ).readAsStringSync();
    final journal = File(
      'lib/features/finance/screens/journal_entries_screen.dart',
    ).readAsStringSync();

    expect(repairs, contains('AppRoutes.journalEntries'));
    expect(repairs, isNot(contains("'/finance/journal',")));
    expect(routes, contains('JournalEntriesScreen(initialRepairId: repairId)'));
    expect(journal, contains('final String? initialRepairId;'));
    expect(journal, contains("where.add('gl.repair_id = ?')"));
  });

  test(
      'P0-03 repair payment reversal is reachable and deletion uses net balance',
      () {
    final repairs = File(
      'lib/features/repairs/screens/repairs_screen.dart',
    ).readAsStringSync();
    final payments = File(
      'lib/features/finance/payments/screens/payment_list_screen.dart',
    ).readAsStringSync();
    final accounting = File(
      'lib/features/repairs/services/repair_auto_accounting_service.dart',
    ).readAsStringSync();

    expect(repairs, contains('دفعات الملف / عكس دفعة'));
    expect(repairs, contains("'allowReverse': true"));
    expect(payments, contains('STAGE1_P0_REPAIR_PAYMENT_SCOPE'));
    expect(payments, contains('PaymentService.reverseReceiptByPaymentId('));
    expect(accounting, contains('STAGE1_P0_REPAIR_DELETE_AFTER_REVERSAL'));
    expect(accounting, contains('final paymentBalance = await _sumPaymentsOn'));
    expect(accounting, contains('paymentBalance.abs() > 0.005'));
  });

  test('P0-04 attendance dropdown rebinds selection by employee id', () {
    final source = File(
      'lib/features/employees/screens/attendance_screen.dart',
    ).readAsStringSync();

    expect(source, contains('STAGE1_P0_ATTENDANCE_SELECTION_RECOVERY'));
    expect(source, contains('selectedEmployee = matches.first'));
    expect(source, contains('Employee? dropdownValue;'));
    expect(source, contains('value: dropdownValue'));
  });

  test('P0-05 purchase PDF uses mobile-native PDF handoff', () {
    final source = File(
      'lib/features/finance/purchases/screens/purchase_details_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import 'package:printing/printing.dart';"));
    expect(source, contains('STAGE1_P0_PURCHASE_PDF_IOS'));
    expect(source,
        contains('Printing.sharePdf(bytes: bytes, filename: fileName)'));
    expect(source, contains('onPressed: _exportPdf'));
  });
}
