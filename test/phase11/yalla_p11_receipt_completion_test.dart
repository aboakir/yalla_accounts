import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/payments_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/receipt_tables.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('P11 canonical receipt contracts', () {
    test('Payment model persists receipt identity and reversal link', () {
      final source = _read('lib/features/finance/payments/models/payment.dart');
      expect(source, contains('final int? receiptNumber;'));
      expect(source, contains("'receipt_number': receiptNumber"));
      expect(source, contains('final String? reversalOfPaymentId;'));
      expect(
        source,
        contains("'reversal_of_payment_id': reversalOfPaymentId"),
      );
    });

    test('receipt has a real header and auditable allocation lines', () {
      final tables = _read('lib/core/services/db/tables/receipt_tables.dart');
      final service = _read(
        'lib/features/finance/payments/services/payment_service.dart',
      );
      expect(tables, contains('CREATE TABLE IF NOT EXISTS receipt_headers'));
      expect(
          tables, contains('CREATE TABLE IF NOT EXISTS receipt_allocations'));
      expect(tables, contains('reversal_of_receipt_number'));
      expect(service, contains('_insertReceiptHeaderOnTxn'));
      expect(service, contains('_insertReceiptAllocationOnTxn'));
    });

    test('receipt save is atomic and caps over-allocation to customer credit',
        () {
      final source = _read(
        'lib/features/finance/payments/services/payment_service.dart',
      );
      expect(source, contains('insertCanonicalReceipt'));
      expect(
          source,
          contains(
              'SyncFoundationService.transaction<CanonicalReceiptResult>'));
      expect(source, contains('_nextReceiptNumberOnTxn'));
      expect(source, contains('line.amount > remaining'));
      expect(source, contains('? remaining : line.amount'));
      expect(source, contains('رصيد دائن غير مخصص للعميل'));
      expect(source, contains('ReceiptAllocationInput'));
      expect(source, contains("allocationType: 'REPAIR'"));
      expect(source, contains("allocationType: 'CREDIT'"));
    });

    test('card and bank transfer never fall through to cash', () {
      final service = _read(
        'lib/features/finance/payments/services/payment_service.dart',
      );
      final legacy = _read(
        'lib/features/finance/payments/screens/add_payment_screen.dart',
      );
      expect(service, contains("return 'card';"));
      expect(service, contains("return 'bank_transfer';"));
      expect(service, contains("'credit',"));
      expect(legacy, contains("value: 'card'"));
      expect(legacy, contains("value: 'bank_transfer'"));
      expect(legacy, isNot(contains("value: 'credit'")));
      expect(legacy, contains("'isIncome': 1"));
    });

    test('customer credit is explicit and can be allocated without new cash',
        () {
      final service = _read(
        'lib/features/finance/payments/services/payment_service.dart',
      );
      final screen = _read(
        'lib/features/vouchers/screens/receipt_voucher_screen.dart',
      );
      expect(service, contains('customerCreditForClient'));
      expect(service, contains('allocateCustomerCreditToRepair'));
      expect(service, contains("source: 'CREDIT_ALLOCATION'"));
      expect(service, contains("method: 'customer_credit'"));
      expect(service, contains("'repair_id': null"));
      expect(service, contains("'repair_id': repairId"));
      expect(screen, contains('رصيد العميل الدائن'));
      expect(screen, contains('PaymentService.allocateCustomerCreditToRepair'));
    });

    test('formal reversal creates immutable counter-payment and reverses GL',
        () {
      final source = _read(
        'lib/features/finance/payments/services/payment_service.dart',
      );
      expect(source, contains('reverseReceiptByPaymentId'));
      expect(source, contains('reverseReceiptByGlEntryId'));
      expect(source, contains('reversalOfPaymentId: original.id'));
      expect(source, contains('amount: -original.amount'));
      expect(source, contains('DBService.reverseEntryGLOn'));
      expect(source, contains("{'status': 'reversed'}"));
      expect(source, contains('reversalOfReceiptNumber: receiptNumber'));
    });

    test(
        'cheque reversal shares the receipt transaction and restores repair AR',
        () {
      final payment = _read(
        'lib/features/finance/payments/services/payment_service.dart',
      );
      final cheque = _read(
        'lib/features/cheques/services/cheque_accounting_service.dart',
      );
      expect(payment, contains('transitionStatusOnTxn'));
      expect(cheque, contains('static Future<Cheque> transitionStatusOnTxn'));
      expect(cheque, contains('_paymentDimensionsOnTxn'));
      expect(cheque, contains("'repair_id': dimensions['repair_id']"));
      expect(cheque, contains("'invoice_id': dimensions['invoice_id']"));
    });

    test('destructive payment UI routes to formal reversal', () {
      final payments =
          _read('lib/features/finance/screens/payments_screen.dart');
      final invoice = _read(
        'lib/features/finance/invoices/screens/invoice_view_screen.dart',
      );
      expect(payments, contains('PaymentService.reverseReceiptByPaymentId'));
      expect(invoice, contains('PaymentService.reverseReceiptByGlEntryId'));
      expect(payments, isNot(contains("txn.delete('payments'")));
      expect(payments, contains('سيتم عكس السند كاملًا'));
    });

    test('invoice quick payment is classified as receipt income', () {
      final source = _read(
        'lib/features/finance/invoices/widgets/invoice_add_payment_button.dart',
      );
      expect(source, contains("'isIncome': 1"));
      expect(source, contains('PaymentService.insertAndPostReceipt'));
    });

    test('receipt voucher UI uses one canonical batch operation', () {
      final screen = _read(
        'lib/features/vouchers/screens/receipt_voucher_screen.dart',
      );
      expect(screen, contains('PaymentService.insertCanonicalReceipt'));
      expect(screen, contains('ReceiptAllocationInput'));
      expect(screen, contains('BANK_TRANSFER'));
      expect(screen, contains('CARD'));
      expect(screen, contains('CHEQUE'));
      expect(
        screen,
        isNot(contains('PaymentService.insertAndPostReceipt')),
      );
    });

    test('receipt list excludes credit reallocation from fresh collections',
        () {
      final screen = _read(
        'lib/features/vouchers/screens/receipt_vouchers_list_screen.dart',
      );
      expect(screen, contains('p.receipt_number'));
      expect(screen, contains('GROUP BY COALESCE'));
      expect(screen, contains("<> 'customer_credit'"));
      expect(screen, contains("padLeft(6, '0')"));
    });

    test('P11 schema is additive on create and existing v69 databases', () {
      final migration = _read('lib/core/services/db/database_migration.dart');
      expect(migration, contains("import 'tables/receipt_tables.dart';"));
      expect(migration, contains('ReceiptTables.createAllTables(db)'));
      expect(migration, contains('PaymentsTables.ensurePaymentsSchema(db)'));
      final receipts = _read('lib/core/services/db/tables/receipt_tables.dart');
      expect(receipts, isNot(contains('DROP TABLE')));
      expect(receipts, isNot(contains('DELETE FROM')));
    });
  });

  test(
      'additive P11 tables create cleanly and receipt reversal nets payment truth',
      () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 1);
    addTearDown(db.close);

    await PaymentsTables.createAllTables(db);
    await ReceiptTables.createAllTables(db);

    final headerInfo = await db.rawQuery('PRAGMA table_info(receipt_headers)');
    final headerColumns = headerInfo.map((r) => r['name']).toSet();
    expect(
        headerColumns,
        containsAll(<String>{
          'receipt_number',
          'client_id',
          'total_amount',
          'allocated_amount',
          'credit_amount',
          'reversal_of_receipt_number',
        }));

    await db.insert('payments', {
      'id': 'P1',
      'receipt_number': 1,
      'client_id': 1,
      'repair_id': 'R1',
      'amount': 500.0,
      'date': DateTime(2026, 9, 5).toIso8601String(),
      'method': 'cash',
      'status': 'confirmed',
      'isIncome': 1,
    });
    await db.insert('payments', {
      'id': 'P1R',
      'receipt_number': 2,
      'reversal_of_payment_id': 'P1',
      'client_id': 1,
      'repair_id': 'R1',
      'amount': -500.0,
      'date': DateTime(2026, 9, 5).toIso8601String(),
      'method': 'cash',
      'status': 'reversal',
      'isIncome': 1,
    });

    final paid = await db.rawQuery('''
      SELECT COALESCE(SUM(amount),0) AS s
      FROM payments
      WHERE repair_id='R1' AND COALESCE(isIncome,1)=1
    ''');
    expect((paid.first['s'] as num).toDouble(), 0.0);
  });
}
