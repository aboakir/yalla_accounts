import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supplier balance is derived only from supplier GL lines', () {
    final s = File('lib/core/services/db/db_service.dart').readAsStringSync();
    final start = s.indexOf('static Future<double> getSupplierBalance');
    final end = s.indexOf(
        '// ==========================================================================',
        start + 10);
    final block = s.substring(start, end);
    expect(block, contains('gl_lines'));
    expect(block, contains('credit-l.debit'));
    expect(block, contains('2200.S'));
    expect(block, isNot(contains('purchase_invoices')));
    expect(block, isNot(contains("FROM payments")));
  });
}
