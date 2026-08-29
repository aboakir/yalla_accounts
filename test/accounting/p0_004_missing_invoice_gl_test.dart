import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sourceFile = File(
    'lib/features/finance/services/invoice_database_service.dart',
  );

  test('P0.004 invoice + GL use the same transaction', () {
    expect(sourceFile.existsSync(), isTrue);
    final source = sourceFile.readAsStringSync();

    final start = source.indexOf(
      'Future<Invoice> createOrGetByRepair({',
    );
    final end = source.indexOf(
      '// 4) Update Paid Amount',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final method = source.substring(start, end);

    expect(
      method.contains('AccountingTables.postInvoiceGLOnTransaction('),
      isTrue,
    );
    expect(method.contains('txn: txn'), isTrue);
    expect(method.contains("source = ? AND source_id = ?"), isTrue);
    expect(method.contains("'post_to_gl': 1"), isTrue);
    expect(method.contains("'gl_entry_id': glId"), isTrue);

    expect(method.contains('catch (_) {}'), isFalse);
    expect(method.contains('AccountingTables.postInvoiceGL('), isFalse);
  });

  test('P0.004 posting fails closed on invalid accounting inputs', () {
    final source = sourceFile.readAsStringSync();

    expect(
      source.contains(
        r'Cannot create/post invoice for repair $repairId without client_id',
      ),
      isTrue,
    );
    expect(
      source.contains(
        r'Cannot create/post invoice for repair $repairId with total <= 0',
      ),
      isTrue,
    );
  });
}
