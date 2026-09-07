import 'package:sqflite/sqflite.dart';

import 'accounting_source_policy.dart';
import 'db/db_service.dart';

/// Read-only Stage 1 accounting integrity/trace API.
class AccountingIntegrityService {
  AccountingIntegrityService._();

  static Future<Map<String, Object?>> traceSource({
    required String source,
    required String sourceId,
  }) async {
    final db = await DBService.database;
    return traceSourceOn(db, source: source, sourceId: sourceId);
  }

  static Future<Map<String, Object?>> traceSourceOn(
    DatabaseExecutor db, {
    required String source,
    required String sourceId,
  }) async {
    final canonical = AccountingSourcePolicy.canonical(source);
    final aliases = AccountingSourcePolicy.aliasesFor(canonical);
    final placeholders = List.filled(aliases.length, '?').join(',');
    final entries = await db.rawQuery(
      'SELECT * FROM gl_entries '
      'WHERE UPPER(source) IN ($placeholders) AND source_id=? '
      'ORDER BY id',
      <Object?>[...aliases, sourceId],
    );
    if (entries.length > 1) {
      throw StateError(
        'Duplicate accounting source identity: $canonical:$sourceId '
        'has ${entries.length} GL entries.',
      );
    }
    if (entries.isEmpty) {
      return <String, Object?>{
        'canonical_source': canonical,
        'source_id': sourceId,
        'posted': false,
        'entry': null,
        'lines': const <Map<String, Object?>>[],
        'source_document': await _sourceDocument(db, canonical, sourceId),
      };
    }

    final entry = entries.single;
    final entryId = (entry['id'] as num).toInt();
    final lines = await db.query(
      'gl_lines',
      where: 'entry_id=?',
      whereArgs: [entryId],
      orderBy: 'id',
    );
    final events = await _queryIfTableExists(
      db,
      'accounting_audit_events',
      where: 'gl_entry_id=?',
      whereArgs: [entryId],
    );

    return <String, Object?>{
      'canonical_source': canonical,
      'source_id': sourceId,
      'posted': true,
      'entry': entry,
      'lines': lines,
      'audit_events': events,
      'source_document': await _sourceDocument(db, canonical, sourceId),
    };
  }

  static Future<Map<String, Object?>> healthReport() async {
    final db = await DBService.database;
    return healthReportOn(db);
  }

  static Future<Map<String, Object?>> healthReportOn(
    DatabaseExecutor db,
  ) async {
    final unbalanced = await db.rawQuery('''
      SELECT e.id, e.source, e.source_id,
             SUM(l.debit-l.credit) AS difference
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      GROUP BY e.id, e.source, e.source_id
      HAVING ABS(SUM(l.debit-l.credit)) >= 0.005
      ORDER BY e.id;
    ''');

    final canonicalExpr =
        AccountingSourcePolicy.sqlCanonicalExpression('source');
    final duplicateSources = await db.rawQuery('''
      SELECT $canonicalExpr AS canonical_source, source_id,
             COUNT(*) AS entry_count, GROUP_CONCAT(id) AS entry_ids,
             GROUP_CONCAT(source) AS raw_sources
      FROM gl_entries
      GROUP BY $canonicalExpr, source_id
      HAVING COUNT(*) > 1;
    ''');

    final orphanLines = await db.rawQuery('''
      SELECT l.id, l.entry_id
      FROM gl_lines l
      LEFT JOIN gl_entries e ON e.id=l.entry_id
      WHERE e.id IS NULL;
    ''');

    final unresolvedParties = await _unresolvedParties(db);
    final issues = unbalanced.length +
        duplicateSources.length +
        orphanLines.length +
        unresolvedParties.length;

    return <String, Object?>{
      'healthy': issues == 0,
      'issue_count': issues,
      'unbalanced_entries': unbalanced,
      'duplicate_source_identities': duplicateSources,
      'orphan_gl_lines': orphanLines,
      'unresolved_party_lines': unresolvedParties,
    };
  }

  static Future<void> assertHealthyOn(DatabaseExecutor db) async {
    final report = await healthReportOn(db);
    if (report['healthy'] != true) {
      throw StateError('Accounting integrity check failed: $report');
    }
  }

  static Future<List<Map<String, Object?>>> _unresolvedParties(
    DatabaseExecutor db,
  ) async {
    if (!await _tableExists(db, 'party_roles')) return const [];
    return db.rawQuery('''
      SELECT l.id AS gl_line_id, l.party_type, l.party_id
      FROM gl_lines l
      LEFT JOIN v_party_gl_lines v ON v.gl_line_id=l.id
      WHERE UPPER(COALESCE(l.party_type,'')) IN
            ('CLIENT','CUSTOMER','SUPPLIER','EMPLOYEE')
        AND (l.party_id IS NULL OR TRIM(l.party_id)='' OR v.canonical_party_id IS NULL)
      ORDER BY l.id;
    ''');
  }

  static Future<Map<String, Object?>?> _sourceDocument(
    DatabaseExecutor db,
    String canonicalSource,
    String sourceId,
  ) async {
    final source = canonicalSource.toUpperCase();
    String? table;
    if (source == 'INVOICE') table = 'invoices';
    if (source == 'PURCHASE') table = 'purchase_invoices';
    if (source == 'VOUCHER') table = 'vouchers';
    if (source == 'EMP_ADV') table = 'employee_advances';
    if (table == null || !await _tableExists(db, table)) return null;
    final rows = await db.query(
      table,
      where: 'id=?',
      whereArgs: [sourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, Object?>>> _queryIfTableExists(
    DatabaseExecutor db,
    String table, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    if (!await _tableExists(db, table)) return const [];
    return db.query(table, where: where, whereArgs: whereArgs);
  }

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }
}
