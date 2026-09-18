const fs = require('fs');
const root = 'F:/yalla network/yalla_accounts/YALLA_ACCOUNTS_UNIFIED_LATEST_20260914';
const read = p => fs.readFileSync(`${root}/${p}`, 'utf8');
const write = (p,s) => fs.writeFileSync(`${root}/${p}`, s, 'utf8');

// 1) Supplier balance: GL is the source of truth.
let db = read('lib/core/services/db/db_service.dart');
db = db.replace(/  static Future<double> getSupplierBalance\(int supplierId\) async \{[\s\S]*?\n  \}\n\n  \/\/ ==========================================================================/,
`  static Future<double> getSupplierBalance(int supplierId) async {
    final db = await database;
    final code = '2200.S\${supplierId.toString().padLeft(4, '0')}';
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS balance
      FROM gl_lines l JOIN accounts a ON a.id=l.account_id
      WHERE a.code=?
    ''', [code]);
    final raw = rows.isEmpty ? 0 : rows.first['balance'];
    return raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
  }

  // ==========================================================================`);
write('lib/core/services/db/db_service.dart', db);
// 2) Draft edit guard.
let edit = read('lib/features/repairs/services/edit_repair_service.dart');
if (!edit.includes('final isFinanciallyApproved')) {
  const needle = "      final parts = _normalizeLines(newParts);";
  const guard = [
    "      final originalStatus = original.status.trim().toUpperCase();",
    "      final isFinanciallyApproved = originalStatus == 'APPROVED' || originalStatus == 'COMPLETED' || original.invoiceId != null;",
    "      if (!isFinanciallyApproved) {",
    "        final parts = _normalizeLines(newParts);",
    "        final works = _normalizeLines(newWorks);",
    "        final newValue = RepairAutoAccountingService.computeAccountingTotal(works: works, parts: parts, notes: notes);",
    "        final map = updatedRepair.copyWith(parts: parts, works: works, fileValue: newValue, notes: notes, status: original.status, updatedAt: DateTime.now()).toMap()..remove('invoice_id')..remove('id');",
    "        await txn.update('repairs', map, where: 'id = ?', whereArgs: [repairId]);",
    "        await _replaceRepairLinesOn(txn, repairId: repairId, parts: parts, works: works);",
    "        await _insertHistory(txn: txn, repairId: repairId, oldValue: original.fileValue, newValue: newValue, editedBy: editedBy, notes: notes);",
    "        return EditRepairResult(success: true, oldValue: original.fileValue, newValue: newValue, difference: _round2(newValue - original.fileValue));",
    "      }",
    ""
  ].join('\n');
  edit = edit.replace(needle, guard + needle);
}
write('lib/features/repairs/services/edit_repair_service.dart', edit);
