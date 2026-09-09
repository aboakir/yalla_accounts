import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('P0.005 voucher supplier payment uses canonical 2200 AP', () {
    final source = _read(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    );
    expect(source.contains('2000.S'), isFalse);
    expect(source.contains('2200.S'), isTrue);
  });

  test('P0.005 outgoing supplier payment avoids legacy 2000 account', () {
    final source = _read(
      'lib/features/finance/payments/services/payment_service.dart',
    );
    expect(source.contains('2000.S'), isFalse);
    expect(source.contains('2200.S'), isTrue);
  });

  test('P0.005 core purchase-payment helper uses canonical supplier resolver',
      () {
    final source = _read(
      'lib/core/services/db/tables/accounting_tables.dart',
    );
    expect(
      source.contains('_ensureSupplierAccountOn(db, supplierId)'),
      isTrue,
    );
  });

  test('P0.005 purchase payment delegates to the central voucher pipeline', () {
    final source = _read(
        'lib/features/finance/purchases/services/purchase_payment_service.dart');
    expect(source.contains('VoucherPaymentService.insertAndPost('), isTrue);
    expect(source.contains("partyType: 'SUPPLIER'"), isTrue);
    expect(source.contains('postEntryGL'), isFalse);
  });
}
