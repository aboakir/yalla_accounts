import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ROOT-ISSUE-EXPORT-001 uses platform-safe downloads abstraction', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('getDownloadsDirectory()')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.endsWith('/core/platform/yalla_path_provider.dart')) {
        continue;
      }
      if (source.contains(
        "import 'package:path_provider/path_provider.dart';",
      )) {
        offenders.add(normalized);
      }
      expect(
        source,
        contains('core/platform/yalla_path_provider.dart'),
        reason: 'Unsafe export path provider in $normalized',
      );
    }
    expect(offenders, isEmpty);
  });

  test('YA-HUMAN-015 receivable payment posts a real receipt', () {
    final source = File(
      'lib/features/finance/screens/accounts_receivable_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('AccountsReceivableService.instance.recordPayment'),
    );
    expect(source, contains('RepairDatabaseService.getRepairById'));
    expect(
      source,
      isNot(contains('Navigator.of(context).pushNamed(AppRoutes.payments)')),
    );
    expect(source, contains('جارٍ التسجيل…'));
  });

  test('YA-HUMAN-006 repairs SQL uses canonical fileValue column', () {
    for (final path in const [
      'lib/features/repairs/screens/vehicles_arrears_screen.dart',
      'lib/features/repairs/screens/debts_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('r.totalFileValue')),
        reason: 'Legacy DB column reference in $path',
      );
      expect(
        source,
        isNot(contains('receivedDate, totalFileValue FROM repairs')),
        reason: 'Legacy SELECT column in $path',
      );
      expect(source, contains('fileValue'));
    }
  });
}
