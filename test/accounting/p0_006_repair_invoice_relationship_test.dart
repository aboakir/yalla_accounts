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

    expect(source.contains('_assertInvoiceMutable('), isTrue);
    expect(
      source.contains(r'Posted invoice $id is immutable.'),
      isTrue,
    );
    expect(
      source.contains(
        'Use a formal credit/debit note or reversal/reissue workflow.',
      ),
      isTrue,
    );
    expect(
      RegExp(r'await _assertInvoiceMutable\(txn, id\);')
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(2),
      reason: 'Both update and delete paths must fail closed once posted.',
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

  test(
      'P0.006 accounted repair cancellation uses formal reversal + soft cancel',
      () {
    final databaseSource = read(
      'lib/features/repairs/services/repair_database_service.dart',
    );
    final accountingSource = read(
      'lib/features/repairs/services/repair_auto_accounting_service.dart',
    );

    expect(
      databaseSource.contains(
        'await RepairAutoAccountingService.deleteRepair(id);',
      ),
      isTrue,
    );

    final start = accountingSource.indexOf(
      'static Future<void> deleteRepair(String repairId) async {',
    );
    expect(start, greaterThanOrEqualTo(0));
    final method = accountingSource.substring(start);

    // Payments must be formally handled before cancellation.
    expect(method.contains('paymentCount > 0'), isTrue);

    // Posted financial history is preserved through reversal, never DELETE.
    expect(method.contains('DBService.reverseEntryGLOn('), isTrue);
    expect(method.contains("tx.delete('gl_entries'"), isFalse);
    expect(method.contains("tx.delete('gl_lines'"), isFalse);

    // The repair is soft-cancelled/archived instead of physically deleted.
    expect(method.contains("'status': cancelledStatus"), isTrue);
    expect(method.contains("'isArchived': 1"), isTrue);
    expect(
      method.contains("'reason': 'DELETE / CANCEL'"),
      isTrue,
    );
    expect(
      method.contains("tx.insert('repair_accounting_adjustments'"),
      isTrue,
    );
  });
}
