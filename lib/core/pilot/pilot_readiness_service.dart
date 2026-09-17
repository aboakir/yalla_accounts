import 'package:sqflite/sqflite.dart';

class PilotReadinessSnapshot {
  const PilotReadinessSnapshot({
    required this.accountingPass,
    required this.unbalancedEntries,
    required this.entriesMissingAudit,
    required this.duplicateSourcePostings,
    required this.pendingSync,
    required this.conflictedSync,
    required this.rejectedSync,
    required this.openLocalConflicts,
    required this.inventoryMovements,
    required this.negativeInventoryBalances,
    required this.accountsReceivable,
    required this.accountsPayable,
    required this.vatPayable,
  });

  final bool accountingPass;
  final int unbalancedEntries;
  final int entriesMissingAudit;
  final int duplicateSourcePostings;
  final int pendingSync;
  final int conflictedSync;
  final int rejectedSync;
  final int openLocalConflicts;
  final int inventoryMovements;
  final int negativeInventoryBalances;
  final double accountsReceivable;
  final double accountsPayable;
  final double vatPayable;
}

class PilotReadinessService {
  const PilotReadinessService._();

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name=? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<int> _count(DatabaseExecutor db, String sql) async {
    final rows = await db.rawQuery(sql);
    if (rows.isEmpty) return 0;
    return (rows.first.values.first as num?)?.toInt() ?? 0;
  }

  static Future<double> _balance(
    DatabaseExecutor db, {
    required String where,
    required bool creditNormal,
  }) async {
    if (!await _tableExists(db, 'accounts') ||
        !await _tableExists(db, 'gl_lines')) {
      return 0;
    }
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit),0) AS debit,
             COALESCE(SUM(l.credit),0) AS credit
      FROM gl_lines l JOIN accounts a ON a.id=l.account_id WHERE $where
    ''');
    final debit = (rows.first['debit'] as num?)?.toDouble() ?? 0;
    final credit = (rows.first['credit'] as num?)?.toDouble() ?? 0;
    return creditNormal ? credit - debit : debit - credit;
  }

  static Future<PilotReadinessSnapshot> inspect(DatabaseExecutor db) async {
    final hasGl = await _tableExists(db, 'gl_entries') &&
        await _tableExists(db, 'gl_lines');
    final unbalanced = hasGl ? await _count(db, '''
          SELECT COUNT(*) FROM (
            SELECT e.id, COUNT(l.id) AS line_count,
              ROUND(COALESCE(SUM(l.debit),0)*100) AS debit_cents,
              ROUND(COALESCE(SUM(l.credit),0)*100) AS credit_cents
            FROM gl_entries e LEFT JOIN gl_lines l ON l.entry_id=e.id
            GROUP BY e.id
            HAVING line_count<2 OR debit_cents<=0 OR debit_cents<>credit_cents
          )
        ''') : 0;
    final missingAudit =
        hasGl && await _tableExists(db, 'accounting_audit_events')
            ? await _count(db, '''SELECT COUNT(*) FROM gl_entries e
          LEFT JOIN accounting_audit_events a ON a.gl_entry_id=e.id
          WHERE a.gl_entry_id IS NULL''')
            : 0;
    final duplicates = hasGl ? await _count(db, '''SELECT COUNT(*) FROM (
          SELECT UPPER(TRIM(source)) AS source_key,TRIM(source_id) AS source_id,COUNT(*) c
          FROM gl_entries GROUP BY source_key,source_id HAVING c>1
        )''') : 0;
    final hasOutbox = await _tableExists(db, 'sync_outbox');
    final pendingSync = hasOutbox
        ? await _count(db,
            "SELECT COUNT(*) FROM sync_outbox WHERE state IN ('PENDING','SENDING')")
        : 0;
    final conflictedSync = hasOutbox
        ? await _count(
            db, "SELECT COUNT(*) FROM sync_outbox WHERE state='CONFLICT'")
        : 0;
    final rejectedSync = hasOutbox
        ? await _count(
            db, "SELECT COUNT(*) FROM sync_outbox WHERE state='REJECTED'")
        : 0;
    final openLocalConflicts = await _tableExists(db, 'sync_conflicts')
        ? await _count(
            db, "SELECT COUNT(*) FROM sync_conflicts WHERE status='open'")
        : 0;
    final inventoryMovements = await _tableExists(db, 'inventory_movements')
        ? await _count(db, 'SELECT COUNT(*) FROM inventory_movements')
        : 0;
    final negativeInventory = await _tableExists(db, 'inventory_stock_balances')
        ? await _count(db,
            'SELECT COUNT(*) FROM inventory_stock_balances WHERE available<0')
        : 0;

    final ar = await _balance(db,
        where: "a.code='1200' OR a.code LIKE '1200.C%'", creditNormal: false);
    final ap = await _balance(db,
        where: "a.code='2100' OR a.code='2200' OR a.code GLOB '2200.S[0-9]*'",
        creditNormal: true);
    final vat = await _balance(db, where: "a.code='2105'", creditNormal: true);

    return PilotReadinessSnapshot(
      accountingPass: unbalanced == 0 && missingAudit == 0 && duplicates == 0,
      unbalancedEntries: unbalanced,
      entriesMissingAudit: missingAudit,
      duplicateSourcePostings: duplicates,
      pendingSync: pendingSync,
      conflictedSync: conflictedSync,
      rejectedSync: rejectedSync,
      openLocalConflicts: openLocalConflicts,
      inventoryMovements: inventoryMovements,
      negativeInventoryBalances: negativeInventory,
      accountsReceivable: ar,
      accountsPayable: ap,
      vatPayable: vat,
    );
  }
}
