import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readFile(String path) => File(path).readAsStringSync();

void main() {
  test('P0.010 v58 data-health migration remains in current DB', () {
    final constants = readFile(
      'lib/core/services/db/database_constants.dart',
    );
    final migration = readFile(
      'lib/core/services/db/database_migration.dart',
    );

    final versionMatch = RegExp(r'dbVersion\s*=\s*(\d+)').firstMatch(constants);
    expect(versionMatch, isNotNull);
    expect(int.parse(versionMatch!.group(1)!), greaterThanOrEqualTo(58));
    expect(
      migration.contains('Upgrade v58 data-health schema applied'),
      isTrue,
    );
    expect(
      migration.contains('data_health_repair_log'),
      isTrue,
    );
    expect(
      migration.contains('invoice_id TEXT NOT NULL'),
      isTrue,
    );
  });

  test('P0.010 permanent health statuses are explicit', () {
    final source = readFile(
      'lib/features/settings/services/data_health_service.dart',
    );

    expect(source.contains('enum DataHealthStatus'), isTrue);
    expect(source.contains('pass,'), isTrue);
    expect(source.contains('warning,'), isTrue);
    expect(source.contains('error,'), isTrue);
    expect(source.contains('repairable,'), isTrue);
  });

  test('P0.010 health checks cover all P0 accounting domains', () {
    final source = readFile(
      'lib/features/settings/services/data_health_service.dart',
    );

    for (final id in <String>[
      'gl_balance',
      'gl_duplicate_source',
      'document_gl_coverage',
      'posting_cache',
      'repair_invoice_link',
      'repair_detail_cache',
      'supplier_account_mapping',
      'legacy_supplier_balance',
      'invoice_settlements',
      'cheque_document_integrity',
      'repair_history_neutralization',
    ]) {
      expect(source.contains("id: '$id'"), isTrue);
    }
  });

  test('P0.010 safe repair never rewrites posted financial history', () {
    final source = readFile(
      'lib/features/settings/services/data_health_service.dart',
    );

    final start = source.indexOf(
      'Future<DataHealthRepairResult> repairSafeIssues()',
    );
    final end = source.indexOf(
      'Future<DataHealthReport> _runWithDb(',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final repairMethod = source.substring(start, end);

    expect(repairMethod.contains('UPDATE gl_entries'), isFalse);
    expect(repairMethod.contains('UPDATE gl_lines'), isFalse);
    expect(repairMethod.contains('DELETE FROM gl_entries'), isFalse);
    expect(repairMethod.contains('DELETE FROM gl_lines'), isFalse);
    expect(repairMethod.contains('UPDATE invoices SET total'), isFalse);
    expect(repairMethod.contains('UPDATE repairs SET fileValue'), isFalse);
    expect(repairMethod.contains('_createBackup(db)'), isTrue);
  });

  test('P0.010 health UI is reachable from settings', () {
    final settings = readFile(
      'lib/features/settings/screens/settings_screen.dart',
    );
    final screen = readFile(
      'lib/features/settings/screens/data_health_screen.dart',
    );

    expect(settings.contains('DataHealthScreen'), isTrue);
    expect(settings.contains('صحة البيانات والمحاسبة'), isTrue);
    expect(screen.contains('إصلاح الآمن'), isTrue);
    expect(screen.contains('تصدير JSON'), isTrue);
  });
}
