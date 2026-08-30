// 📁 lib/features/finance/reports/providers/general_ledger_provider.dart
//
// GeneralLedgerProvider — مزوّدات دفتر الأستاذ:
// - accountsProvider: يجلب قائمة الحسابات (id, code, name, type, normal_balance).
// - generalLedgerProvider: يُرجع صفوف القيود لحساب محدد ضمن فترة.
// - يحسب الرصيد التراكمي في الدارت (بدون اعتماد على window functions).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/reports/providers/reports_providers.dart';

@immutable
class GlAccount {
  final int id;
  final String code;
  final String name;
  final String type; // ASSET/LIABILITY/EQUITY/REVENUE/EXPENSE
  final String? normalBalance; // DEBIT/CREDIT (قد تكون null بقديم)

  const GlAccount({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.normalBalance,
  });

  String get display => '${code.isNotEmpty ? '$code — ' : ''}$name';
}

@immutable
class LedgerRow {
  final int entryId;
  final DateTime date;
  final String ref;
  final String source;
  final String sourceId;
  final String note;
  final double debit;
  final double credit;
  final double running; // رصيد تراكمي بعد هذا الصف

  const LedgerRow({
    required this.entryId,
    required this.date,
    required this.ref,
    required this.source,
    required this.sourceId,
    required this.note,
    required this.debit,
    required this.credit,
    required this.running,
  });
}

/// قائمة الحسابات مرتبة بالكود ثم الاسم
final accountsProvider =
    FutureProvider.autoDispose<List<GlAccount>>((ref) async {
  final db = await DBService.database;
  // تأمين الأعمدة المطلوبة حتى لو كانت DB قديمة
  await db.execute('''
    CREATE TABLE IF NOT EXISTS accounts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE')),
      normal_balance TEXT
    )
  ''');
  final rows = await db.query(
    'accounts',
    columns: ['id', 'code', 'name', 'type', 'normal_balance'],
    orderBy:
        'CASE WHEN code IS NULL OR code = "" THEN 1 ELSE 0 END, code ASC, name ASC',
  );
  return rows
      .map((m) => GlAccount(
            id: (m['id'] as int),
            code: (m['code'] ?? '').toString(),
            name: (m['name'] ?? '').toString(),
            type: (m['type'] ?? '').toString(),
            normalBalance: (m['normal_balance']?.toString()),
          ))
      .toList();
});

/// مزوّد دفتر الأستاذ: يأخذ accountId + الفترة من reportsRangeProvider
final generalLedgerProvider = FutureProvider.family
    .autoDispose<List<LedgerRow>, int>((ref, accountId) async {
  final db = await DBService.database;

  // الفترة من المزوّد العام اللي عندك
  final range = ref.read(reportsRangeProvider);

  // قراءة normal_balance للحساب لتحديد اتجاه الرصيد
  String normal = 'DEBIT';
  {
    final r = await db.query('accounts',
        columns: ['normal_balance'],
        where: 'id=?',
        whereArgs: [accountId],
        limit: 1);
    final v = r.isNotEmpty ? (r.first['normal_balance']?.toString() ?? '') : '';
    if (v == 'CREDIT') normal = 'CREDIT';
  }

  // الجلب من gl_lines/gl_entries
  final rs = await db.rawQuery('''
    SELECT
      e.id      AS entry_id,
      e.date    AS date,
      IFNULL(e.ref,'')    AS ref,
      IFNULL(e.source,'') AS source,
      IFNULL(e.source_id,'') AS source_id,
      IFNULL(e.note,'')   AS note,
      CAST(l.debit  AS REAL) AS debit,
      CAST(l.credit AS REAL) AS credit
    FROM gl_lines l
    JOIN gl_entries e ON e.id = l.entry_id
    WHERE l.account_id = ?
      AND e.date >= ? AND e.date <= ?
    ORDER BY e.date ASC, e.id ASC, l.id ASC
  ''', [
    accountId,
    range.start.toIso8601String(),
    range.end.toIso8601String(),
  ]);

  // حساب الرصيد التراكمي
  double running = 0.0;
  List<LedgerRow> out = [];
  for (final m in rs) {
    final d = _toD(m['debit']);
    final c = _toD(m['credit']);
    if (normal == 'DEBIT') {
      running += d - c;
    } else {
      running += c - d;
    }
    out.add(LedgerRow(
      entryId: (m['entry_id'] as int),
      date: DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now(),
      ref: (m['ref'] ?? '').toString(),
      source: (m['source'] ?? '').toString(),
      sourceId: (m['source_id'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      debit: d,
      credit: c,
      running: double.parse(running.toStringAsFixed(2)),
    ));
  }

  return out;
});

double _toD(Object? v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}
