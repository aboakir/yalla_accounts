import 'package:sqflite/sqflite.dart';

class LiquidityStatement {
  const LiquidityStatement(this.rows, this.opening, this.debit, this.credit);
  final List<Map<String, Object?>> rows;
  final double opening, debit, credit;
  double get closing => opening + debit - credit;
}

/// Search changes visible rows, never the actual account balance.
class LiquidityLedgerService {
  static Future<LiquidityStatement> load(DatabaseExecutor db, int accountId,
      {DateTime? from, DateTime? to, String query = ''}) async {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    double number(Object? n) => (n as num?)?.toDouble() ?? 0;
    final where = <String>['l.account_id=?'];
    final args = <Object?>[accountId];
    double opening = 0;
    if (from != null) {
      opening = number((await db.rawQuery(
              'SELECT COALESCE(SUM(l.debit-l.credit),0) n FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id WHERE l.account_id=? AND DATE(e.date)<DATE(?)',
              [accountId, day(from)]))
          .single['n']);
      where.add('DATE(e.date)>=DATE(?)');
      args.add(day(from));
    }
    if (to != null) {
      where.add('DATE(e.date)<=DATE(?)');
      args.add(day(to));
    }
    final rows = await db.rawQuery("""
      SELECT e.id entry_id,e.date,e.ref,e.source,e.source_id,e.note,
        a.code account_code,a.name account_name,l.debit,l.credit,l.invoice_id,l.repair_id
      FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE ${where.join(' AND ')} ORDER BY e.date,e.id,l.id
    """, args);
    var running = opening, debit = 0.0, credit = 0.0;
    final visible = <Map<String, Object?>>[];
    final search = query.trim().toLowerCase();
    for (final row in rows) {
      debit += number(row['debit']);
      credit += number(row['credit']);
      running += number(row['debit']) - number(row['credit']);
      if (search.isEmpty ||
          [
            'ref',
            'note',
            'source',
            'source_id',
            'account_code',
            'account_name',
            'invoice_id',
            'repair_id'
          ].any((k) =>
              (row[k]?.toString() ?? '').toLowerCase().contains(search))) {
        visible.add({...row, 'running_balance': running});
      }
    }
    return LiquidityStatement(visible, opening, debit, credit);
  }
}
