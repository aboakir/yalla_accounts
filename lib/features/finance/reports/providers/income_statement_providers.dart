// 📁 lib/features/finance/reports/providers/income_statement_providers.dart
//
// Income Statement Provider — GL-only (v29)
//
// يعتمد على جدول accounts + gl_entries + gl_lines.
// يسحب مصروفات (5xxx) وإيرادات (4xxx) ضمن الفترة، ويجمعها.
// لا وهميات. لا journal_entries.
// نوسع لاحقًا للتكاليف/المخزون لو فيه جداول جاهزة.
//
// الخرج:
// {
//   revenue: double,
//   expenses: double,
//   netIncome: double,
//   rows: [ {code, name, type, debit, credit, balance}, ... ]
// }

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'reports_providers.dart'; // لنطاق التاريخ

final incomeStatementProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final range = ref.watch(reportsRangeProvider);
  final db = await DBService.database;

  final rows = await db.rawQuery('''
    SELECT
      a.code            AS code,
      a.name            AS name,
      a.type            AS type,
      a.normal_balance  AS normal_balance,
      IFNULL(SUM(l.debit), 0)  AS debit,
      IFNULL(SUM(l.credit), 0) AS credit
    FROM accounts a
    JOIN gl_lines l ON l.account_id = a.id
    JOIN gl_entries e ON e.id = l.entry_id
    WHERE e.date >= ? AND e.date <= ?
      AND (
            a.code LIKE '4%'  -- إيرادات
         OR a.code LIKE '5%'  -- مصروفات
      )
    GROUP BY a.code, a.name, a.type, a.normal_balance
    ORDER BY a.code ASC
  ''', [
    range.start.toIso8601String(),
    DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59)
        .toIso8601String(),
  ]);

  double toD(v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double revenue = 0;
  double expenses = 0;

  final outRows = <Map<String, dynamic>>[];

  for (final r in rows) {
    final code = r['code']?.toString() ?? '';
    final name = r['name']?.toString() ?? '';
    final nb = (r['normal_balance'] ?? '').toString().toUpperCase();
    final debit = toD(r['debit']);
    final credit = toD(r['credit']);
    final balance = nb == 'CREDIT' ? (credit - debit) : (debit - credit);

    // تجميع حسب طبيعة الحساب
    if (code.startsWith('4')) revenue += balance;
    if (code.startsWith('5')) expenses += balance;

    outRows.add({
      'code': code,
      'name': name,
      'type': r['type']?.toString() ?? '',
      'debit': debit,
      'credit': credit,
      'balance': balance,
    });
  }

  final net = revenue - expenses;

  return {
    'revenue': revenue,
    'expenses': expenses,
    'netIncome': net,
    'rows': outRows,
  };
});
