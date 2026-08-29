import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('P0.003 invoice UI resolves posting from GL', () {
    final source = _read(
      'lib/features/finance/invoices/screens/invoice_view_screen.dart',
    );

    expect(source.contains("WHERE source = ? AND source_id = ?"), isTrue);
    expect(source.contains("['INVOICE', widget.invoiceId]"), isTrue);
    expect(source.contains("final stored = inv?['gl_entry_id'];"), isFalse);
  });

  test('P0.003 voucher post synchronizes compatibility status', () {
    final source = _read(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    );

    expect(source.contains("'gl_entry_id': glId"), isTrue);
    expect(source.contains("'is_posted': 1"), isTrue);
    expect(source.contains("'posted_at': DateTime.now()"), isTrue);
  });

  test('P0.003 voucher model does not trust is_posted', () {
    final source = _read(
      'lib/features/vouchers/models/voucher_payment_model.dart',
    );

    expect(
      source.contains('isPosted: glEntryId != null && glEntryId != 0'),
      isTrue,
    );
    expect(source.contains("(map['is_posted'] == 1)"), isFalse);
  });

  test('P0.003 unposted receipts are detected from GL existence', () {
    final source = _read(
      'lib/features/finance/payments/screens/unposted_payments_screen.dart',
    );

    expect(source.contains('NOT EXISTS'), isTrue);
    expect(source.contains("e.source = 'PAYMENT'"), isTrue);
    expect(source.contains('p.isIncome = 1'), isTrue);
    expect(
      source.contains('WHERE gl_entry_id IS NULL OR gl_entry_id=0'),
      isFalse,
    );
  });
}
