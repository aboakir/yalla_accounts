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

  test('P0.005 purchase payment debits AP and credits payment account', () {
    final source = _read(
      'lib/features/finance/purchases/services/purchase_payment_service.dart',
    );
    expect(
      source.contains('Supplier payment reduces Accounts Payable.'),
      isTrue,
    );
    expect(
      source.contains('Cash/bank/cheques leave the business.'),
      isTrue,
    );
    expect(source.contains('"isIncome": 0'), isTrue);
    expect(
        source.contains('_ensureSupplierApAccount(txn, supplierId)'), isTrue);
  });
}
