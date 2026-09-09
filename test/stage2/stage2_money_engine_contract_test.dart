import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('Stage2 payment vouchers use formal reversal and audit trail', () {
    final source = read(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    );

    expect(source.contains('static Future<void> reverseVoucher('), isTrue);
    expect(source.contains('DBService.reverseEntryGLOn('), isTrue);
    expect(source.contains('ChequeAccountingService.transitionStatusOnTxn('),
        isTrue);
    expect(source.contains("action: 'PAYMENT_VOUCHER_REVERSED'"), isTrue);
    expect(source.contains("'status': 'REVERSED'"), isTrue);
    expect(
        source.contains("txn.delete(\n        'invoice_settlements'"), isTrue);
  });

  test('Stage2 payment voucher validates party and original reference', () {
    final source = read(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    );

    expect(source.contains('_validateVoucherOnTxn('), isTrue);
    expect(source.contains("'suppliers'"), isTrue);
    expect(source.contains("'employees'"), isTrue);
    expect(source.contains("'clients'"), isTrue);
    expect(
      source.contains(
        'Referenced purchase invoice does not belong to this supplier.',
      ),
      isTrue,
    );
    expect(
      source.contains(
        'Supplier payment exceeds the referenced invoice remaining amount.',
      ),
      isTrue,
    );
  });

  test('Stage2 receipt reversal remains canonical in PaymentService', () {
    final source = read(
      'lib/features/finance/payments/services/payment_service.dart',
    );

    expect(source.contains('reverseReceiptByPaymentId'), isTrue);
    expect(source.contains('reverseReceipt('), isTrue);
    expect(source.contains('_reversePaymentLineOnTxn'), isTrue);
    expect(source.contains('Formal receipt reversal'), isTrue);
  });

  test('Stage2 user lists hide technical ids and reversed totals', () {
    final payments = read(
      'lib/features/vouchers/screens/payment_vouchers_list_screen.dart',
    );
    final receipts = read(
      'lib/features/vouchers/screens/receipt_vouchers_list_screen.dart',
    );

    expect(payments.contains('child: Text("GL"'), isFalse);
    expect(
      payments.contains("COALESCE(v.status,'POSTED') <> 'REVERSED'"),
      isTrue,
    );
    expect(payments.contains('VoucherPaymentService.reverseVoucher('), isTrue);
    expect(
      payments.contains('purchase_invoices\n          SET paid_total'),
      isFalse,
    );
    expect(
      payments.contains(
        'voucherId: row["voucher_number"]?.toString() ?? "P-UNNUMBERED"',
      ),
      isTrue,
    );

    expect(
      receipts.contains(
        'if (rawNumber == null) return row["id"].toString()',
      ),
      isFalse,
    );
    expect(receipts.contains('voucherId: _receiptLabel(row)'), isTrue);
  });
}
