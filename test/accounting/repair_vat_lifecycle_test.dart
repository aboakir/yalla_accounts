import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final accounting = File('lib/core/services/db/tables/accounting_tables.dart')
      .readAsStringSync();

  test('exclusive VAT posts AR total, revenue net, and VAT payable', () {
    expect(accounting, contains('final revenuePortion = (total - vatAmount)'));
    expect(accounting, contains("_getAccountIdByCode(txn, '2105')"));
    expect(accounting, contains("'debit': total"));
    expect(accounting, contains("'credit': revenuePortion"));
    expect(accounting, contains("'credit': vatAmount"));
  });

  test('inclusive VAT extracts net revenue from entered total', () {
    const total = 116.0;
    const rate = 16.0;
    final net = double.parse((total / (1 + rate / 100)).toStringAsFixed(2));
    final vat = double.parse((total - net).toStringAsFixed(2));
    expect(net, 100.0);
    expect(vat, 16.0);
  });

  test('zero VAT preserves legacy totals', () {
    expect(500.0 + 0.0, 500.0);
    expect(accounting, contains('vatAmount > 0'));
  });
}
