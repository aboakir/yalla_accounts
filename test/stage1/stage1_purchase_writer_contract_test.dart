import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Stage1 legacy PurchaseService cannot write a parallel ledger path', () {
    final source = File(
      'lib/features/finance/purchases/services/purchase_service.dart',
    ).readAsStringSync();

    expect(source.contains('PurchaseInvoiceService.createInvoice('), isTrue);
    expect(source.contains('DBService.postEntryGL'), isFalse);
    expect(
        RegExp(r'''\.insert\(\s*['"]purchase_invoices['"]''').hasMatch(source),
        isFalse);
    expect(source.contains('PURCHASE_INVOICE'), isFalse);
  });
}
