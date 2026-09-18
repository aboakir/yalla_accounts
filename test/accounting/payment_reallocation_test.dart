import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final s = File('lib/features/finance/payments/services/payment_service.dart')
      .readAsStringSync();

  test('repair payment reallocation moves AR dimension without moving cash',
      () {
    final start = s.indexOf('allocateCustomerCreditToRepair');
    expect(start, greaterThanOrEqualTo(0));
    final block = s.substring(
        start,
        s.indexOf(
            'static Future<Map<String, Object?>> _receiptSnapshot', start));
    expect(block, contains("source: 'CREDIT_ALLOCATION'"));
    expect(RegExp("'account_id': arAccountId").allMatches(block).length, 2);
    expect(block, isNot(contains("code='1000'")));
    expect(block, isNot(contains("code='1010'")));
  });

  test('customer credit allocation is capped by available credit', () {
    expect(s, contains('if (available < applied) applied = available;'));
  });

  test('customer credit allocation is capped by repair balance', () {
    expect(s,
        contains('if (remaining < applied) applied = remaining.toDouble();'));
  });
}
