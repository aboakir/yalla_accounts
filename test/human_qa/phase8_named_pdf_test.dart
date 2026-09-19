import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('YA-HUMAN-009 receipt vouchers list generates a valid PDF', () async {
    final dir = await Directory.systemTemp.createTemp('receipt_pdf_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    try {
      final bytes = await YallaPdfService.generateReceiptVoucherListPdf(
        rows: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'RC-000001',
            'date': '2026-09-19T10:00:00',
            'clientName': 'عميل اختبار',
            'amount': 350.0,
            'method': 'cash',
          },
        ],
        totalToday: 350,
        totalMonth: 350,
        generatedAt: DateTime(2026, 9, 19, 10),
      );

      expect(bytes.length, greaterThan(1000));
      expect(bytes.take(4).toList(), <int>[37, 80, 68, 70]);
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('YA-HUMAN-014 customer AR PDF uses canonical save service', () {
    final service = File(
      'lib/core/pdf/yalla_pdf_service.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/finance/screens/accounts_receivable_screen.dart',
    ).readAsStringSync();

    expect(service, contains("fileName: 'accounts_receivable.pdf'"));
    expect(service, contains("module: 'exports'"));
    expect(screen, contains('generateAccountsReceivablePdf'));
    expect(
      service,
      isNot(contains('File("\${dir.path}/accounts_receivable.pdf")')),
    );
  });

  test('YA-HUMAN-026 cheques report PDF uses safe export directory', () {
    final source = File(
      'lib/features/cheques/screens/cheques_report_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("core/platform/yalla_path_provider.dart"),
    );
    expect(source, contains('await pdf.save()'));
    expect(source, contains('cheques_report_'));
    expect(
      source,
      isNot(contains("package:path_provider/path_provider.dart")),
    );
  });
}
