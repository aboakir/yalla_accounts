// 📁 lib/features/reports/providers/trial_balance_provider.dart
//
// TrialBalanceProvider — ميزان مراجعة من GL v28.
// يعتمد join بين gl_lines و gl_entries لتصفية النطاق الزمني.
// يرجّع صفوف: code,name,type,normal_balance,debit,credit,net_debit,net_credit.

import 'package:yalla_accounts/core/services/db_service.dart';

class TrialBalanceRow {
  final String code;
  final String name;
  final String type; // ASSET/LIABILITY/...
  final String normalBalance; // DEBIT/CREDIT
  final double debit;
  final double credit;
  final double netDebit;
  final double netCredit;

  TrialBalanceRow({
    required this.code,
    required this.name,
    required this.type,
    required this.normalBalance,
    required this.debit,
    required this.credit,
    required this.netDebit,
    required this.netCredit,
  });
}

class TrialBalanceProvider {
  /// يجلب ميزان مراجعة اختياريًا بنطاق تاريخ.
  /// إن لم تُمرِّر from/to يأخذ كل الفترات.
  static Future<List<TrialBalanceRow>> fetch({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await DBService.database;

    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('ge.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('ge.date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT
        a.code AS code,
        a.name AS name,
        a.type AS type,
        a.normal_balance AS normal_balance,
        ROUND(COALESCE(SUM(gl.debit),0),2) AS debit,
        ROUND(COALESCE(SUM(gl.credit),0),2) AS credit
      FROM accounts a
      LEFT JOIN gl_lines gl ON gl.account_id = a.id
      LEFT JOIN gl_entries ge ON ge.id = gl.entry_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      GROUP BY a.code,a.name,a.type,a.normal_balance
      ORDER BY a.code
    ''', args);

    return rows.map((m) {
      final d = _toD(m['debit']);
      final c = _toD(m['credit']);
      final netD = d > c ? (d - c) : 0.0;
      final netC = c > d ? (c - d) : 0.0;
      return TrialBalanceRow(
        code: (m['code'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        type: (m['type'] ?? '').toString(),
        normalBalance: (m['normal_balance'] ?? '').toString(),
        debit: d,
        credit: c,
        netDebit: _round(netD),
        netCredit: _round(netC),
      );
    }).toList();
  }

  static double _toD(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '0') ?? 0.0;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}
