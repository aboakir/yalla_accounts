import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/payment_voucher_read_service.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory temp;
  late dynamic session;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('human_pv_gate_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'human-qa');
  });
  tearDown(() async {
    await session.endEphemeralPreviewSession();
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Map<String, Object?> employeeRow(
    String id,
    String code,
    String status,
  ) =>
      {
        'id': id,
        'full_name': 'Employee $code',
        'employee_code': code,
        'job_title': 'Painter',
        'hire_date': '2026-01-01',
        'phone': '',
        'email': '',
        'address': '',
        'status': status,
        'base_salary': 1200.0,
        'allowances': 0.0,
        'deductions': 0.0,
        'advances': 0.0,
        'total_work_days': 0,
        'total_hours': 0.0,
        'absences': 0,
        'late_days': 0,
        'notes': '',
        'created_at': '2026-01-01T00:00:00Z',
        'payment_method': 'cash',
        'work_days_per_week': 6,
        'hours_per_day': 8,
      };

  Future<int> addSupplier(String name) =>
      db.insert('suppliers', {'name': name});

  Future<void> addInvoice(
    String id,
    int supplierId,
    double total,
  ) async {
    await db.insert('purchase_invoices', {
      'id': id,
      'supplier_id': supplierId,
      'amount_total': total,
      'paid_total': 0.0,
      'date': '2026-09-19',
      'method': 'credit',
      'status': 'UNPAID',
    });
  }

  Future<void> postPurchase(
    String invoiceId,
    int supplierId,
    double total,
  ) async {
    final ap = await db.insert('accounts', {
      'code': '2200.S${supplierId.toString().padLeft(4, '0')}',
      'name': 'Supplier $supplierId',
      'type': 'LIABILITY',
      'normal_balance': 'CREDIT',
    });
    final expense = await db.insert('accounts', {
      'code': '5999.H$supplierId',
      'name': 'Human QA purchase',
      'type': 'EXPENSE',
      'normal_balance': 'DEBIT',
    });
    await AccountingTables.postEntryGLOn(
      ex: db,
      date: DateTime(2026, 9, 19),
      source: 'PURCHASE_INVOICE',
      sourceId: invoiceId,
      lines: [
        {
          'account_id': expense,
          'debit': total,
          'credit': 0.0,
          'invoice_id': invoiceId,
        },
        {
          'account_id': ap,
          'debit': 0.0,
          'credit': total,
          'party_type': 'SUPPLIER',
          'party_id': supplierId,
          'invoice_id': invoiceId,
        },
      ],
    );
  }

  VoucherPayment supplierVoucher(
    String id,
    int supplierId,
    String invoiceId,
    double amount,
  ) =>
      VoucherPayment(
        id: id,
        voucherType: 'PAYMENT',
        partyType: 'SUPPLIER',
        partyId: '$supplierId',
        amount: amount,
        currency: 'ILS',
        date: DateTime(2026, 9, 19),
        method: 'cash',
        reference: invoiceId,
      );
  test('TEST-PV-001..004 supplier invoice list is scoped and accurate',
      () async {
    final s1 = await addSupplier('Supplier One');
    final s2 = await addSupplier('Supplier Two');
    await addInvoice('INV-1', s1, 1000);
    await addInvoice('INV-2', s2, 2000);
    await postPurchase('INV-1', s1, 1000);
    await postPurchase('INV-2', s2, 2000);

    final rows = await PaymentVoucherReadService.openInvoicesForSupplier(
      s1,
      executor: db,
    );
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'INV-1');
    expect(rows.single['amount_total'], 1000.0);
    expect(rows.single['paid_total'], 0.0);
    expect(rows.single['remaining'], 1000.0);

    final balance = await PaymentVoucherReadService.supplierBalance(
      s1,
      executor: db,
    );
    expect(balance, isNotNull);
    expect(balance!.payableBalance, 1000.0);
  });
  test('TEST-PV-005..008 + 013 partial/full payment updates one truth',
      () async {
    final supplier = await addSupplier('Supplier Pay');
    await addInvoice('INV-PAY', supplier, 1000);
    await postPurchase('INV-PAY', supplier, 1000);

    await VoucherPaymentService.insertAndPost(
      voucher: supplierVoucher('PV-PART', supplier, 'INV-PAY', 400),
      partyName: 'Supplier Pay',
      database: db,
    );

    var rows = await PaymentVoucherReadService.openInvoicesForSupplier(
      supplier,
      executor: db,
    );
    expect(rows.single['paid_total'], 400.0);
    expect(rows.single['remaining'], 600.0);
    var balance = await PaymentVoucherReadService.supplierBalance(
      supplier,
      executor: db,
    );
    expect(balance!.payableBalance, 600.0);

    await expectLater(
      VoucherPaymentService.insertAndPost(
        voucher: supplierVoucher('PV-OVER', supplier, 'INV-PAY', 700),
        partyName: 'Supplier Pay',
        database: db,
      ),
      throwsStateError,
    );

    await VoucherPaymentService.insertAndPost(
      voucher: supplierVoucher('PV-FULL', supplier, 'INV-PAY', 600),
      partyName: 'Supplier Pay',
      database: db,
    );
    rows = await PaymentVoucherReadService.openInvoicesForSupplier(
      supplier,
      executor: db,
    );
    expect(rows, isEmpty);
    balance = await PaymentVoucherReadService.supplierBalance(
      supplier,
      executor: db,
    );
    expect(balance!.payableBalance, 0.0);

    await VoucherPaymentService.insertAndPost(
      voucher: supplierVoucher('PV-FULL', supplier, 'INV-PAY', 600),
      partyName: 'Supplier Pay',
      database: db,
    );
    final gl = await db.query(
      'gl_entries',
      where: 'source=? AND source_id=?',
      whereArgs: ['VOUCHER', 'PV-FULL'],
    );
    expect(gl, hasLength(1));
  });

  test('TEST-PV-009..012 active employee and payroll entitlement are enforced',
      () async {
    await db.insert('employees', employeeRow('E-ACT', 'A-1', 'active'));
    await db.insert('employees', employeeRow('E-OFF', 'I-1', 'inactive'));

    final employees =
        await PaymentVoucherReadService.activeEmployees(executor: db);
    expect(employees.map((e) => e['id']), contains('E-ACT'));
    expect(employees.map((e) => e['id']), isNot(contains('E-OFF')));

    final missing = VoucherPayment(
      id: 'PV-NO-EMP',
      voucherType: 'PAYMENT',
      partyType: 'EMPLOYEE',
      partyId: '',
      amount: 50,
      currency: 'ILS',
      date: DateTime(2026, 9, 19),
      method: 'cash',
      source: 'EMP_ADV',
      sourceId: 'PV-NO-EMP',
    );
    await expectLater(
      VoucherPaymentService.insertAndPost(
        voucher: missing,
        partyName: '',
        database: db,
      ),
      throwsStateError,
    );

    await db.insert('payroll_runs', {
      'id': 'RUN-1',
      'employee_id': 'E-ACT',
      'gross': 1200.0,
      'allowances': 0.0,
      'deductions': 0.0,
      'advance_applied': 0.0,
      'net': 1200.0,
      'amount_paid': 0.0,
      'status': 'ACCRUED',
      'period_start': '2026-09-01',
      'period_end': '2026-09-30',
      'accrual_date': '2026-09-30',
    });

    final salary = VoucherPayment(
      id: 'PV-SALARY',
      voucherType: 'PAYMENT',
      partyType: 'EMPLOYEE',
      partyId: 'E-ACT',
      amount: 1200,
      currency: 'ILS',
      date: DateTime(2026, 9, 30),
      method: 'cash',
      reference: 'RUN-1',
      source: 'PAYROLL_ENTITLEMENT',
      sourceId: 'RUN-1',
    );
    await VoucherPaymentService.insertAndPost(
      voucher: salary,
      partyName: 'Employee A-1',
      database: db,
    );
    final run = (await db.query(
      'payroll_runs',
      where: 'id=?',
      whereArgs: ['RUN-1'],
    ))
        .single;
    expect(run['amount_paid'], 1200.0);
    expect(run['status'], 'PAID');

    final saved = await db.query(
      'vouchers',
      where: 'id=?',
      whereArgs: ['PV-SALARY'],
    );
    expect(saved.single['party_id'], 'E-ACT');
    expect(saved.single['source_id'], 'RUN-1');
  });

  test('payment voucher UI exposes supplier and employee controls', () {
    final source = File(
      'lib/features/vouchers/screens/payment_voucher_screen.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('PaymentVoucherReadService.openInvoicesForSupplier'),
    );
    expect(source, contains("'إجمالي الرصيد المستحق'"));
    expect(source, contains("'المبلغ المدفوع بهذا السند'"));
    expect(source, contains("'الرصيد بعد الدفعة'"));
    expect(source, contains('PaymentVoucherReadService.activeEmployees()'));
    expect(source, contains("'اختر الموظف'"));
    expect(source, contains("'راتب مستحق'"));
    expect(source, contains('amountCtrl.text = remaining.toStringAsFixed(2)'));
  });
}
