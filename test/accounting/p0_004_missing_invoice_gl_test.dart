import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('P0.004 invoice + GL stay atomic through current posting pipeline', () {
    final invoiceSource = read(
      'lib/features/finance/services/invoice_database_service.dart',
    );

    final start = invoiceSource.indexOf(
      'Future<Invoice> createOrGetByRepair({',
    );
    final end = invoiceSource.indexOf(
      '// 4) Update Paid Amount',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final method = invoiceSource.substring(start, end);

    // Current architecture intentionally routes:
    // InvoiceDatabaseService -> DBService -> PostingEngine -> AccountingTables
    // while preserving the SAME DatabaseExecutor transaction throughout.
    expect(
      method.contains('DBService.postInvoiceGLOnTransaction('),
      isTrue,
    );
    expect(method.contains('txn: txn'), isTrue);
    expect(method.contains("source = ? AND source_id = ?"), isTrue);
    expect(method.contains("'post_to_gl': 1"), isTrue);
    expect(method.contains("'gl_entry_id': glId"), isTrue);

    // The invoice method must not open an independent GL posting path.
    expect(method.contains('catch (_) {}'), isFalse);
    expect(method.contains('DBService.postInvoiceGL('), isFalse);
    expect(method.contains('AccountingTables.postInvoiceGL('), isFalse);

    final dbService = read('lib/core/services/db/db_service.dart');
    final dbStart = dbService.indexOf(
      'static Future<int> postInvoiceGLOnTransaction({',
    );
    final dbEnd = dbService.indexOf(
      'static Future<int> postInvoiceGLFromId',
      dbStart,
    );
    expect(dbStart, greaterThanOrEqualTo(0));
    expect(dbEnd, greaterThan(dbStart));
    final dbMethod = dbService.substring(dbStart, dbEnd);
    expect(dbMethod.contains('PostingEngine.postInvoiceOn('), isTrue);
    expect(dbMethod.contains('txn: txn'), isTrue);

    final postingEngine = read('lib/core/services/posting_engine.dart');
    final engineStart = postingEngine.indexOf(
      'static Future<int> postInvoiceOn({',
    );
    final engineEnd = postingEngine.indexOf(
      'static Future<int> postInvoiceFromId',
      engineStart,
    );
    expect(engineStart, greaterThanOrEqualTo(0));
    expect(engineEnd, greaterThan(engineStart));
    final engineMethod = postingEngine.substring(engineStart, engineEnd);
    expect(
      engineMethod.contains('AccountingTables.postInvoiceGLOnTransaction('),
      isTrue,
    );
    expect(engineMethod.contains('txn: txn'), isTrue);
  });

  test('P0.004 posting fails closed on invalid accounting inputs', () {
    final source = read(
      'lib/features/finance/services/invoice_database_service.dart',
    );

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
