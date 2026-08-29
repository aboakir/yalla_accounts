import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readFile(String path) => File(path).readAsStringSync();

void main() {
  test('P0.007 payment voucher retry is side-effect safe', () {
    final source = readFile(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    );

    expect(
      source.contains('Retry of an already-posted voucher stops here.'),
      isTrue,
    );
    expect(
      source.contains('uq_settlements_voucher_invoice'),
      isTrue,
    );
    expect(
      source.contains('preferredInvoiceId: postingVoucher.reference!.trim()'),
      isTrue,
    );
    expect(
      source.contains('preferredInvoiceId: int.tryParse'),
      isFalse,
    );
    expect(
      source.contains('invoice_id TEXT NOT NULL'),
      isTrue,
    );
  });

  test('P0.007 receipts never invent invoices', () {
    final source = readFile(
      'lib/features/finance/payments/services/payment_service.dart',
    );

    expect(source.contains('_findInvoiceIdOnTxn'), isTrue);
    expect(source.contains('_ensureInvoiceIdOnTxn'), isFalse);
    expect(
      source.contains("'invoices',"),
      isFalse,
      reason: 'PaymentService must not insert invoices.',
    );
  });

  test('P0.007 posted receipts are immutable', () {
    final source = readFile(
      'lib/features/finance/payments/services/payment_service.dart',
    );

    expect(
      source.contains('Posted receipt'),
      isTrue,
    );
    expect(
      source.contains('formal reversal/correcting receipt workflow'),
      isTrue,
    );
  });

  test('P0.007 voucher screens prevent double-submit', () {
    final paymentScreen = readFile(
      'lib/features/vouchers/screens/payment_voucher_screen.dart',
    );
    final receiptScreen = readFile(
      'lib/features/vouchers/screens/receipt_voucher_screen.dart',
    );

    expect(paymentScreen.contains('bool _isSaving = false;'), isTrue);
    expect(receiptScreen.contains('bool _isSaving = false;'), isTrue);
    expect(
      paymentScreen.contains('onPressed: _isSaving ? null : _saveVoucher'),
      isTrue,
    );
    expect(
      receiptScreen.contains('onPressed: _isSaving ? null : _saveVoucher'),
      isTrue,
    );
  });

  test('P0.008 supersedes the temporary cheque gate with real linkage', () {
    final voucherSource = readFile(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    );
    final receiptSource = readFile(
      'lib/features/finance/payments/services/payment_service.dart',
    );

    expect(voucherSource.contains('createLinkedChequeOnTxn'), isTrue);
    expect(receiptSource.contains('createLinkedChequeOnTxn'), isTrue);
    expect(
      receiptSource.contains('temporarily blocked until P0.008'),
      isFalse,
    );
  });
}
