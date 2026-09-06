// 📁 lib/core/services/reports_gl_service.dart
//
// ReportsGLService — تقارير محاسبية مباشرة من جداول GL:
// - Trial Balance
// - General Ledger (حركة حساب)
// - AR Aging للعملاء
// - AP Aging للموردين
//
// بدون بيانات افتراضية. يعتمد على:
// accounts(id,code,name,type)
// gl_entries(id,date,...)
// gl_lines(id,entry_id,account_id,debit,credit,party_type,party_id)
// clients(id, name, account_id?)
// suppliers(id, name, account_id?)

import 'package:yalla_accounts/core/services/db_service.dart';

class ReportsGLService {
  ReportsGLService._();

  // ---------- Trial Balance ----------
  static Future<List<Map<String, Object?>>> trialBalance({
    required DateTime from,
    required DateTime to,
    List<int>? accountIds, // اختياري
  }) async {
    final db = await DBService.database;

    final where = <String>['e.date >= ? AND e.date <= ?'];
    final args = <Object>[from.toIso8601String(), to.toIso8601String()];

    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      where.add('l.account_id IN ($placeholders)');
      args.addAll(accountIds);
    }

    final sql = '''
      SELECT
        a.id           AS account_id,
        a.code         AS code,
        a.name         AS name,
        a.type         AS type,
        ROUND(SUM(l.debit), 2)  AS total_debit,
        ROUND(SUM(l.credit), 2) AS total_credit,
        ROUND(SUM(l.debit - l.credit), 2) AS balance
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      JOIN accounts a   ON a.id = l.account_id
      WHERE ${where.join(' AND ')}
      GROUP BY a.id, a.code, a.name, a.type
      ORDER BY a.code ASC
    ''';

    return db.rawQuery(sql, args);
  }

  // ---------- General Ledger (حركة حساب) ----------
  static Future<List<Map<String, Object?>>> generalLedger({
    required int accountId,
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await DBService.database;

    // رصيد افتتاحي حتى قبل from
    final openingSql = '''
      SELECT ROUND(COALESCE(SUM(l.debit - l.credit),0), 2) AS opening
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? AND e.date < ?
    ''';
    final openingRes =
        await db.rawQuery(openingSql, [accountId, from.toIso8601String()]);
    final opening = _numToDouble(openingRes.first['opening']);

    final linesSql = '''
      SELECT
        e.id     AS entry_id,
        e.date   AS date,
        e.ref    AS ref,
        e.source AS source,
        e.source_id AS source_id,
        e.note   AS note,
        ROUND(l.debit,2)  AS debit,
        ROUND(l.credit,2) AS credit
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? AND e.date >= ? AND e.date <= ?
      ORDER BY e.date ASC, e.id ASC, l.id ASC
    ''';
    final rows = await db.rawQuery(
        linesSql, [accountId, from.toIso8601String(), to.toIso8601String()]);

    // احسب رصيد جارٍ
    double running = opening;
    final out = <Map<String, Object?>>[];
    out.add({
      'kind': 'opening',
      'balance': _round(opening),
    });

    for (final r in rows) {
      final d = _numToDouble(r['debit']);
      final c = _numToDouble(r['credit']);
      running = _round(running + d - c);
      out.add({
        'kind': 'line',
        'entry_id': r['entry_id'],
        'date': r['date'],
        'ref': r['ref'],
        'source': r['source'],
        'source_id': r['source_id'],
        'note': r['note'],
        'debit': d,
        'credit': c,
        'balance': running,
      });
    }

    out.add({
      'kind': 'closing',
      'balance': _round(running),
    });

    return out;
  }

  // ---------- AR Aging (العملاء) ----------
  // buckets: 0-30, 31-60, 61-90, 90+
  static Future<List<Map<String, Object?>>> arAging({
    required DateTime asOf,
  }) async {
    final db = await DBService.database;

    // نجلب كل حركات ذمم العملاء من GL من CLIENT/CUSTOMER أو من ربط الحسابات.
    final sql = '''
      WITH ar AS (
        SELECT
          COALESCE(c.id, CAST(l.party_id AS INTEGER)) AS client_id,
          c.name AS client_name,
          e.date AS date,
          (l.debit - l.credit) AS delta
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        LEFT JOIN clients c ON c.account_id = l.account_id
        WHERE
          (
            -- حسابات AR المربوطة مباشرة بعملاء
            c.account_id = l.account_id
            OR
            -- أو استخدام party_type كبديل
            (UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER') AND l.party_id IS NOT NULL)
          )
          AND e.date <= ?
      )
      SELECT
        client_id,
        COALESCE(client_name, 'عميل غير مخصص') AS client_name,
        -- عمر الأيام
        SUM(CASE WHEN julianday(?) - julianday(date) <= 30 THEN delta ELSE 0 END) AS bkt_0_30,
        SUM(CASE WHEN julianday(?) - julianday(date) > 30 AND julianday(?) - julianday(date) <= 60 THEN delta ELSE 0 END) AS bkt_31_60,
        SUM(CASE WHEN julianday(?) - julianday(date) > 60 AND julianday(?) - julianday(date) <= 90 THEN delta ELSE 0 END) AS bkt_61_90,
        SUM(CASE WHEN julianday(?) - julianday(date) > 90 THEN delta ELSE 0 END) AS bkt_90_plus,
        SUM(delta) AS total
      FROM ar
      GROUP BY client_id, client_name
      HAVING ABS(total) > 0.000001
      ORDER BY client_name COLLATE NOCASE ASC
    ''';

    final iso = asOf.toIso8601String();
    final args = [iso, iso, iso, iso, iso, iso, iso];

    final rows = await db.rawQuery(sql, args);

    // عادةً الرصيد المدين = مستحق على العميل.
    // لو عندك تعريف مختلف، عدّل العرض فقط.
    return rows;
  }

  // ---------- AP Aging (الموردين) ----------
  static Future<List<Map<String, Object?>>> apAging({
    required DateTime asOf,
  }) async {
    final db = await DBService.database;

    final sql = '''
      WITH ap AS (
        SELECT
          s.id AS supplier_id,
          s.name AS supplier_name,
          e.date AS date,
          -- نفترض أن حسابات AP نوعها LIABILITY وبذلك الائتمان يزيد الرصيد لصالح المورد
          (l.credit - l.debit) AS delta
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        JOIN suppliers s ON s.account_id = l.account_id
        WHERE e.date <= ?
      )
      SELECT
        supplier_id,
        supplier_name,
        SUM(CASE WHEN julianday(?) - julianday(date) <= 30 THEN delta ELSE 0 END) AS bkt_0_30,
        SUM(CASE WHEN julianday(?) - julianday(date) > 30 AND julianday(?) - julianday(date) <= 60 THEN delta ELSE 0 END) AS bkt_31_60,
        SUM(CASE WHEN julianday(?) - julianday(date) > 60 AND julianday(?) - julianday(date) <= 90 THEN delta ELSE 0 END) AS bkt_61_90,
        SUM(CASE WHEN julianday(?) - julianday(date) > 90 THEN delta ELSE 0 END) AS bkt_90_plus,
        SUM(delta) AS total
      FROM ap
      GROUP BY supplier_id, supplier_name
      HAVING ABS(total) > 0.000001
      ORDER BY supplier_name COLLATE NOCASE ASC
    ''';

    final iso = asOf.toIso8601String();
    final args = [iso, iso, iso, iso, iso, iso, iso];

    return db.rawQuery(sql, args);
  }

  // ---------- Utils ----------
  static double _numToDouble(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}
