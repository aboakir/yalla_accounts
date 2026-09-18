import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editing an unapproved repair stays operational and posts nothing', () {
    final s = File('lib/features/repairs/services/edit_repair_service.dart')
        .readAsStringSync();
    expect(s, contains('final isFinanciallyApproved'));
    expect(s, contains('if (!isFinanciallyApproved)'));
    final branchStart = s.indexOf('if (!isFinanciallyApproved)');
    final branchEnd = s.indexOf(
        'await RepairAutoAccountingService.reconcileEditedValueOn(',
        branchStart);
    final block = s.substring(branchStart, branchEnd);
    expect(block, contains("status: original.status"));
    expect(block, isNot(contains('reconcileEditedValueOn')));
    expect(block, isNot(contains('createInvoice')));
    expect(block, isNot(contains('postEntryGL')));
  });
}
