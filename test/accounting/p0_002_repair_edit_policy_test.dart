import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P0.002 repair edits cannot silently mutate posted accounting', () {
    final file = File(
      'lib/features/repairs/services/edit_repair_service.dart',
    );

    expect(file.existsSync(), isTrue);

    final source = file.readAsStringSync();

    expect(source.contains('AccountingTables.reverseRepairGL('), isFalse);
    expect(source.contains('AccountingTables.adjustRepairGL('), isFalse);
    expect(
      source.contains(
        'InvoiceDatabaseService.instance.recomputeForRepair(',
      ),
      isFalse,
    );

    expect(
      source.contains(
        'Client reassignment requires a dedicated audited workflow.',
      ),
      isTrue,
    );

    expect(source.contains('isLedgerSynced: false'), isTrue);
  });

  test('P0.002 preserves repair edit history', () {
    final source = File(
      'lib/features/repairs/services/edit_repair_service.dart',
    ).readAsStringSync();

    expect(source.contains('repair_edit_history'), isTrue);
    expect(source.contains("'old_value': oldValue"), isTrue);
    expect(source.contains("'new_value': newValue"), isTrue);
    expect(source.contains("'difference': newValue - oldValue"), isTrue);
  });
}
