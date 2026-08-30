// 📁 lib/features/finance/reports/services/trial_balance_service.dart
//
// TrialBalanceService — SQL-only عبر DBService (GL v29)
// يحسب مجاميع مدين/دائن لكل حساب ضمن الفترة، ثم يشتق الرصيد بحسب نوع الحساب:
//   ASSET/EXPENSE  → balance = debit - credit  (طبيعة مدين)
//   LIABILITY/EQUITY/REVENUE → balance = credit - debit (طبيعة دائن)
// يحافظ على ظهور كل الحسابات حتى لو بلا حركة عبر LEFT JOIN.
//
// أعمدة الإخراج لكل صف:
//   code, name, type, total_debit, total_credit, balance
//
// فهارس مقترحة:
//   CREATE INDEX IF NOT EXISTS idx_gl_lines_account ON gl_lines(account_id);
//   CREATE INDEX IF NOT EXISTS idx_gl_entries_date  ON gl_entries(date);

import 'package:yalla_accounts/core/services/db_service.dart';

class TrialBalanceService {
  TrialBalanceService._();

  static Future<List<Map<String, Object?>>> fetch({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await DBService.database;

    final sql = '''
      WITH agg AS (
        SELECT
          a.id            AS account_id,
          IFNULL(a.code,'')  AS code,
          a.name          AS name,
          a.type          AS type, -- ASSET / LIABILITY / EQUITY / REVENUE / EXPENSE
          IFNULL(SUM(l.debit), 0)  AS total_debit,
          IFNULL(SUM(l.credit), 0) AS total_credit
        FROM accounts a
        LEFT JOIN gl_lines   l ON l.account_id = a.id
        LEFT JOIN gl_entries e ON e.id = l.entry_id
                              AND e.date >= ?
                              AND e.date <= ?
        GROUP BY a.id, a.code, a.name, a.type
      )
      SELECT
        code,
        name,
        type,
        total_debit,
        total_credit,
        -- balance rule by type
        CASE
          WHEN type IN ('ASSET','EXPENSE')
            THEN ROUND(total_debit - total_credit, 2)
          ELSE
            ROUND(total_credit - total_debit, 2)
        END AS balance
      FROM agg
      ORDER BY
        CASE type
          WHEN 'ASSET' THEN 1
          WHEN 'LIABILITY' THEN 2
          WHEN 'EQUITY' THEN 3
          WHEN 'REVENUE' THEN 4
          WHEN 'EXPENSE' THEN 5
          ELSE 6
        END,
        code ASC, name ASC
    ''';

    final args = [from.toIso8601String(), to.toIso8601String()];
    final rows = await db.rawQuery(sql, args);

    // تطبيع الأرقام لثنائية المنازل.
    List<Map<String, Object?>> out = [];
    for (final r in rows) {
      double d = _toD(r['total_debit']);
      double c = _toD(r['total_credit']);
      double bal = _toD(r['balance']);
      out.add({
        'code': (r['code'] ?? '').toString(),
        'name': (r['name'] ?? '').toString(),
        'type': (r['type'] ?? '').toString(),
        'total_debit': _fix2(d),
        'total_credit': _fix2(c),
        'balance': _fix2(bal),
      });
    }
    return out;
  }

  static double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double _fix2(double x) => double.parse(x.toStringAsFixed(2));
}
