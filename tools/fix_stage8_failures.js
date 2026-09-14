const fs = require('fs');
const root = 'F:/yalla network/yalla_accounts/YALLA_ACCOUNTS_UNIFIED_LATEST_20260914';
const p = `${root}/lib/features/repairs/services/edit_repair_service.dart`;
let s = fs.readFileSync(p, 'utf8');

const draftStart = s.indexOf('if (!isFinanciallyApproved)');
const reconcile = s.indexOf('await RepairAutoAccountingService.reconcileEditedValueOn(');
if (draftStart >= 0 && reconcile > draftStart) {
  const before = s.slice(0, reconcile);
  const after = s.slice(reconcile);
  s = before.replace('await _insertHistory(', 'await _insertDraftHistory(') + after;
}

if (!s.includes('static Future<void> _insertDraftHistory')) {
  const marker = '  static Future<void> _insertHistory({';
  const helper = `  static Future<void> _insertDraftHistory({\n    required DatabaseExecutor txn,\n    required String repairId,\n    required double oldValue,\n    required double newValue,\n    required String editedBy,\n    required String notes,\n  }) => _insertHistory(txn: txn, repairId: repairId, oldValue: oldValue, newValue: newValue, editedBy: editedBy, notes: notes);\n\n`;
  s = s.replace(marker, helper + marker);
}
fs.writeFileSync(p, s, 'utf8');

const tp = `${root}/test/accounting/repair_draft_edit_no_posting_test.dart`;
let t = fs.readFileSync(tp, 'utf8');
t = t.replace(
  "    final branchEnd =\n        s.indexOf('final parts = _normalizeLines(newParts);', branchStart + 10);",
  "    final branchEnd = s.indexOf('await RepairAutoAccountingService.reconcileEditedValueOn(', branchStart);"
);
fs.writeFileSync(tp, t, 'utf8');
