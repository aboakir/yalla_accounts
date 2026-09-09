import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('Stage 4 salary payment is only a linked payment voucher', () {
    final payrollDb = read(
      'lib/features/employees/services/payroll_database_service.dart',
    );
    final vouchers = read(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    );

    expect(payrollDb, contains("source: 'PAYROLL_ENTITLEMENT'"));
    expect(payrollDb, contains('VoucherPaymentService.insertAndPost'));
    expect(payrollDb, contains("reference: runId"));
    expect(payrollDb, contains("sourceId: runId"));
    expect(payrollDb, contains('syncPaymentState'));

    expect(vouchers, contains("'PAYROLL_ENTITLEMENT'"));
    expect(vouchers, contains('2140.E\$empId'));
    expect(
        vouchers,
        contains(
            'Salary payment voucher must reference its payroll entitlement'));
    expect(
        vouchers,
        contains(
            'Salary payment exceeds payroll entitlement remaining amount'));
    expect(vouchers, contains('_syncPayrollRunFromVouchers'));
  });

  test('Stage 4 disables all legacy direct salary payment writers', () {
    final salaryService = read(
      'lib/features/employees/services/salary_service.dart',
    );
    final salaryPayment = read(
      'lib/features/employees/services/salary_payment_database_service.dart',
    );
    final salaryDb = read(
      'lib/features/employees/services/salary_database_service.dart',
    );
    final dashboard = read(
      'lib/features/employees/screens/employee_dashboard_screen.dart',
    );
    final salaryScreen = read(
      'lib/features/employees/screens/salary_screen.dart',
    );

    expect(salaryService, contains('Direct salary payment is disabled'));
    expect(
        salaryPayment, contains('Legacy salary_payments writes are disabled'));
    expect(salaryPayment, isNot(contains('postEntryGL')));
    expect(salaryDb, contains('Legacy direct salary payment is disabled'));
    expect(salaryDb, isNot(contains("source: 'PAYROLL_PAYMENT'")));
    expect(dashboard, isNot(contains('SalaryService.paySalary')));
    expect(salaryScreen, isNot(contains('SalaryDatabaseService.paySalary')));
    expect(salaryScreen, isNot(contains('PayrollDatabaseService.pay(')));
    expect(salaryScreen, contains('PaymentVoucherScreen('));
    expect(salaryScreen, contains('payrollRun:'));
  });
}
