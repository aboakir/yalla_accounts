import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readFile(String path) => File(path).readAsStringSync();

void main() {
  test('P0.009 repair-lines migration remains part of current DB', () {
    final source = readFile(
      'lib/core/services/db/database_constants.dart',
    );

    final versionMatch = RegExp(r'dbVersion\s*=\s*(\d+)').firstMatch(source);
    expect(versionMatch, isNotNull);
    expect(int.parse(versionMatch!.group(1)!), greaterThanOrEqualTo(57));
  });

  test('P0.009 repair_lines schema enforces line integrity', () {
    final source = readFile(
      'lib/core/services/db/tables/repair_tables.dart',
    );

    expect(source.contains('CHECK(qty > 0)'), isTrue);
    expect(source.contains('CHECK(price >= 0)'), isTrue);
    expect(
      source.contains(
        'CHECK(total >= 0 AND ABS(total - (qty * price)) <= 0.01)',
      ),
      isTrue,
    );
    expect(source.contains('_rebuildRepairLinesV57'), isTrue);
    expect(source.contains('if (oldV < 57)'), isTrue);
  });

  test('P0.009 new repair save normalizes JSON and repair_lines together', () {
    final source = readFile(
      'lib/features/repairs/services/repair_save_service.dart',
    );

    expect(source.contains('final normalizedParts = _normalizeLines'), isTrue);
    expect(source.contains('final normalizedWorks = _normalizeLines'), isTrue);
    expect(source.contains('if (qty <= 0) qty = 1.0;'), isTrue);
    expect(source.contains("'total': _roundLine(qty * price)"), isTrue);
    expect(source.contains('parts: normalizedParts'), isTrue);
    expect(source.contains('works: normalizedWorks'), isTrue);

    expect(
      source.contains("'qty': _asDouble(p['qty'])"),
      isFalse,
    );
  });

  test('P0.009 RepairDatabaseService keeps derived lines in same transaction',
      () {
    final source = readFile(
      'lib/features/repairs/services/repair_database_service.dart',
    );

    expect(source.contains('_replaceRepairLinesOn'), isTrue);
    expect(source.contains('parts: normalizedParts'), isTrue);
    expect(source.contains('works: normalizedWorks'), isTrue);
    expect(source.contains("..remove('invoice_id')"), isTrue);

    expect(
      source.contains('Never create/recompute/repost the invoice'),
      isTrue,
    );
  });

  test('P0.009 migration never posts or rewrites accounting', () {
    final source = readFile(
      'lib/core/services/db/tables/repair_tables.dart',
    );

    final start = source.indexOf(
      'static Future<void> _rebuildRepairLinesV57',
    );
    final end = source.indexOf(
      'static Future<void> ensureRepairsSchema(',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final migration = source.substring(start, end);

    expect(migration.contains("'invoices'"), isFalse);
    expect(migration.contains("'gl_entries'"), isFalse);
    expect(migration.contains("'gl_lines'"), isFalse);
    expect(migration.contains("'fileValue':"), isFalse);
  });
}
