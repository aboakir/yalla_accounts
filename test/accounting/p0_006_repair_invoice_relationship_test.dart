import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('P0.006 repair save/update do not auto-create accounting', () {
    final source = read(
      'lib/features/repairs/services/repair_database_service.dart',
    );

    final insertStart = source.indexOf(
      'static Future<String> insertRepair(Repair r)',
    );
    final insertEnd = source.indexOf(
      '// INSERT + RETURN INVOICE',
      insertStart,
    );
    final insert = source.substring(insertStart, insertEnd);

    expect(insert.contains("tx.insert('invoices'"), isFalse);
    expect(insert.contains('postInvoiceGL('), isFalse);

    final updateStart = source.indexOf(
      'static Future<void> updateRepair(Repair r)',
    );
    final updateEnd = source.indexOf('// DELETE', updateStart);
    final update = source.substring(updateStart, updateEnd);

    expect(update.contains("tx.insert('invoices'"), isFalse);
    expect(update.contains('postInvoiceGL('), isFalse);
    expect(update.contains("..remove('invoice_id')"), isTrue);
  });

  test('P0.006 posted invoice is immutable', () {
    final source = read(
      'lib/features/finance/invoices/services/invoice_service.dart',
    );

    expect(
      source.contains(
        r'Posted invoice $existingId is immutable.',
      ),
      isTrue,
    );
    expect(
      source.contains(
        'Use a formal credit/debit note or reversal/reissue workflow.',
      ),
      isTrue,
    );
    expect(
      source.contains('return DBService.inTx((txn) async {'),
      isTrue,
    );
  });

  test('P0.006 invoice payment maintenance does not rewrite total', () {
    final source = read(
      'lib/features/finance/services/invoice_database_service.dart',
    );

    final start = source.indexOf('Future<void> updatePaidAmount({');
    final end = source.indexOf('// 5) Recompute Whole Invoice', start);
    final method = source.substring(start, end);

    expect(method.contains("'total':"), isFalse);
    expect(method.contains("'paid': _round(newPaid)"), isTrue);
  });

  test('P0.006 accounted repair deletion fails closed', () {
    final source = read(
      'lib/features/repairs/services/repair_database_service.dart',
    );

    expect(
      source.contains(
        'Cannot delete an invoiced/accounted repair.',
      ),
      isTrue,
    );
    expect(source.contains("tx.delete('gl_entries'"), isFalse);
  });
}
