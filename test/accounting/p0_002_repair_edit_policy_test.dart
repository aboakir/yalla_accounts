import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P0.002 repair edits use audited additive accounting reconciliation',
      () {
    final file = File(
      'lib/features/repairs/services/edit_repair_service.dart',
    );

    expect(file.existsSync(), isTrue);

    final source = file.readAsStringSync();

    // EditRepairService must not mutate posted GL/invoices directly. It delegates
    // value changes to the canonical additive accounting reconciliation service.
    expect(source.contains('AccountingTables.reverseRepairGL('), isFalse);
    expect(source.contains('AccountingTables.adjustRepairGL('), isFalse);
    expect(
      source.contains(
        'InvoiceDatabaseService.instance.recomputeForRepair(',
      ),
      isFalse,
    );
    expect(
      source.contains('RepairAutoAccountingService.reconcileEditedValueOn('),
      isTrue,
    );

    // Client reassignment is explicitly blocked in the generic edit path so AR
    // ownership cannot move silently between customers.
    expect(
      source.contains('updatedRepair.clientId != original.clientId'),
      isTrue,
    );
    expect(
      source.contains('تغيير العميل لملف قائم يحتاج إجراء مستقل'),
      isTrue,
    );

    // After successful reconciliation the repair cache may be marked synced;
    // posted documents themselves remain immutable and deltas are additive.
    expect(source.contains('isLedgerEnabled: true'), isTrue);
    expect(source.contains('isLedgerSynced: true'), isTrue);
    expect(source.contains("approvedBy: 'AUTO_EDIT'"), isTrue);
  });

  test('P0.002 preserves repair edit history after reconciliation', () {
    final source = File(
      'lib/features/repairs/services/edit_repair_service.dart',
    ).readAsStringSync();

    expect(source.contains('repair_edit_history'), isTrue);
    expect(source.contains("'old_value': _round2(oldValue)"), isTrue);
    expect(source.contains("'new_value': _round2(newValue)"), isTrue);
    expect(
      source.contains("'difference': _round2(newValue - oldValue)"),
      isTrue,
    );

    final reconcileIndex = source.indexOf(
      'await RepairAutoAccountingService.reconcileEditedValueOn(',
    );
    final historyIndex = source.indexOf('await _insertHistory(');
    expect(reconcileIndex, greaterThanOrEqualTo(0));
    expect(historyIndex, greaterThan(reconcileIndex));
  });
}
