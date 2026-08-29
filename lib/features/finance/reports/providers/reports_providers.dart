// 📁 lib/features/finance/reports/providers/reports_providers.dart
//
// Reports Providers — GL-only (v29)
// - يعتمد فقط على: accounts, gl_entries, gl_lines, clients عبر DBService.
// - Trial Balance: يُرجع لكل حساب ضمن الفترة: code, name, type, total_debit, total_credit, balance.
//   ⚠️ تم إصلاح التصفية التاريخية باستخدام SUM(CASE WHEN ... THEN ... ELSE 0 END) لضمان حصر المجاميع داخل الفترة.
// - AR Aging (FIFO): يجمع كل حسابات AR (code='1200' أو '1200.%') ويطبق FIFO على مستوى العميل.
//   يُرجِع: client_id, client_name, client_type, current, d30, d60, d90, over90, total_due
//
// ملاحظات:
// - party_type في GL تُعامل بحساسية منخفضة: نقبل 'CUSTOMER' و 'CLIENT'.
// - ربط العميل يتم عبر CAST(l.party_id AS INTEGER) ⇐ clients.id INTEGER.
// - نهاية الفترة تُحسب كـ نهاية اليوم 23:59:59 لضمان شمول يوم النهاية.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

/// نطاق التاريخ لتقاريرنا
class ReportDateRange {
  final DateTime start;
  final DateTime end;
  const ReportDateRange({required this.start, required this.end});

  /// الشهر الحالي
  factory ReportDateRange.currentMonth() {
    final now = DateTime.now();
    final s = DateTime(now.year, now.month, 1);
    final e = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    return ReportDateRange(start: s, end: e);
  }
}

/// مزوّد نطاق الفترة
final reportsRangeProvider =
    StateProvider<ReportDateRange>((ref) => ReportDateRange.currentMonth());

String _iso(DateTime d) => d.toIso8601String();

double _toD(Object? v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

double _round(double v) => double.parse(v.toStringAsFixed(2));

DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

/// ───────────────────────── ميزان المراجعة (GL) ─────────────────────────
/// يُرجع List<Map> بالمفاتيح: code, name, type, total_debit, total_credit, balance
final trialBalanceProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final range = ref.watch(reportsRangeProvider);
  final db = await DBService.database;
  final startIso = _iso(range.start);
  final endIso = _iso(_endOfDay(range.end));

  // ملاحظة مهمة: نستخدم CASE WHEN على تاريخ gl_entries لضمان قصر التجميع داخل الفترة.
  final rows = await db.rawQuery('''
    SELECT 
      a.id        AS id,
      a.code      AS code,
      a.name      AS name,
      a.type      AS type,
      IFNULL(SUM(CASE WHEN e.date >= ? AND e.date <= ? THEN l.debit  ELSE 0 END), 0) AS total_debit,
      IFNULL(SUM(CASE WHEN e.date >= ? AND e.date <= ? THEN l.credit ELSE 0 END), 0) AS total_credit
    FROM accounts a
    LEFT JOIN gl_lines   l ON l.account_id = a.id
    LEFT JOIN gl_entries e ON e.id = l.entry_id
    GROUP BY a.id, a.code, a.name, a.type
    ORDER BY a.code ASC
  ''', [startIso, endIso, startIso, endIso]);

  return rows.map((m) {
    final td = _toD(m['total_debit']);
    final tc = _toD(m['total_credit']);
    return <String, dynamic>{
      'code': (m['code'] ?? '').toString(),
      'name': (m['name'] ?? '').toString(),
      'type': (m['type'] ?? '').toString(),
      'total_debit': td,
      'total_credit': tc,
      'balance': _round(td - tc),
    };
  }).toList();
});

/// ───────────────────────── أعمار الذمم للعملاء (GL) — FIFO ─────────────────────────
/// المنهج:
/// - نقرأ كل حركات حسابات AR (code='1200' أو '1200.%') حتى نهاية اليوم للفترة.
/// - party_type: نقبل 'CUSTOMER' و'CLIENT' (غير حساس لحالة الأحرف).
/// - نفصل الفواتير (debit) والمدفوعات (credit) لكل عميل.
/// - FIFO: نستهلك المدفوعات من أقدم فاتورة.
/// - نوزّع المتبقي على السلال: current(≤30) / d30(31–60) / d60(61–90) / d90(91–120) / over90(>120).
/// الناتج لكل عميل: client_id, client_name, client_type, current, d30, d60, d90, over90, total_due.
final arAgingProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final range = ref.watch(reportsRangeProvider);
  final db = await DBService.database;

  final DateTime end = _endOfDay(range.end);
  final String endIso = _iso(end);

  // احصل على كل حسابات الذمم (الرئيسي + الفرعية)
  final accRows = await db.rawQuery(
    "SELECT id FROM accounts WHERE code='1200' OR code LIKE '1200.%'",
  );
  if (accRows.isEmpty) return <Map<String, dynamic>>[];

  final accIds = accRows
      .map((m) => m['id'])
      .where((v) => v != null)
      .map((v) => v is int ? v : int.tryParse(v.toString()) ?? -1)
      .where((v) => v > 0)
      .toList();
  if (accIds.isEmpty) return <Map<String, dynamic>>[];

  final placeholders = List.filled(accIds.length, '?').join(',');
  final args = <Object?>[...accIds, endIso];

  // نسحب سطور AR حتى endIso مع ربط اسم ونوع العميل
  final rows = await db.rawQuery('''
    SELECT
      e.date                         AS date,
      l.debit                        AS debit,
      l.credit                       AS credit,
      UPPER(IFNULL(l.party_type,'')) AS party_type,
      l.party_id                     AS party_id,
      c.name                         AS client_name,
      c.type                         AS client_type
    FROM gl_lines l
    JOIN gl_entries e ON e.id = l.entry_id
    LEFT JOIN clients c ON c.id = CAST(l.party_id AS INTEGER)
    WHERE l.account_id IN ($placeholders)
      AND e.date <= ?
      AND l.party_id IS NOT NULL
      AND UPPER(IFNULL(l.party_type,'')) IN ('CUSTOMER','CLIENT')
    ORDER BY e.date ASC, e.id ASC, l.id ASC
  ''', args);

  // FIFO per client
  final Map<int, _ClientBucket> clients = {};
  for (final m in rows) {
    final cid = int.tryParse((m['party_id'] ?? '').toString());
    if (cid == null) continue;

    final cname = (m['client_name'] ?? 'غير مذكور').toString();
    final ctypeRaw = (m['client_type'] ?? '').toString().trim().toLowerCase();
    final ctype = (ctypeRaw == 'insurance' ||
            ctypeRaw == 'شركة تأمين' ||
            ctypeRaw == 'تأمين')
        ? 'شركة تأمين'
        : 'أفراد';

    final rec =
        clients.putIfAbsent(cid, () => _ClientBucket(cid, cname, ctype));

    final iso = (m['date'] ?? '').toString();
    DateTime d;
    try {
      d = DateTime.parse(iso);
    } catch (_) {
      d = end;
    }

    final debit = _toD(m['debit']);
    final credit = _toD(m['credit']);

    if (debit > 0) rec.invoices.add(_Leg(date: d, amount: debit));
    if (credit > 0) rec.credits.add(_Leg(date: d, amount: credit));
  }

  // استهلاك المدفوعات من أقدم الفواتير
  for (final rec in clients.values) {
    rec.invoices.sort((a, b) => a.date.compareTo(b.date));
    rec.credits.sort((a, b) => a.date.compareTo(b.date));

    var pool = rec.credits.fold<double>(0, (s, x) => s + x.amount);

    for (final inv in rec.invoices) {
      if (pool <= 0) break;
      final take = inv.remaining <= pool ? inv.remaining : pool;
      inv.remaining = _round(inv.remaining - take);
      pool = _round(pool - take);
    }

    // توزيع المتبقي حسب عمر الفاتورة حتى end
    for (final inv in rec.invoices) {
      final rem = inv.remaining;
      if (rem <= 0) continue;

      final days = end.difference(inv.date).inDays;
      if (days <= 30) {
        rec.current += rem;
      } else if (days <= 60) {
        rec.d30 += rem;
      } else if (days <= 90) {
        rec.d60 += rem;
      } else if (days <= 120) {
        rec.d90 += rem;
      } else {
        rec.over90 += rem;
      }
    }
  }

  // إخراج منسّق للشاشة
  final list = clients.values.map((r) => r.toMap()).toList()
    ..removeWhere((m) => _toD(m['total_due']).abs() <= 0.000001)
    ..sort((a, b) => _toD(b['total_due']).compareTo(_toD(a['total_due'])));

  return list;
});

/// ───────── Types داخلية لمعادلة الأعمار ─────────

class _Leg {
  final DateTime date;
  final double amount;
  double remaining;
  _Leg({required this.date, required this.amount}) : remaining = amount;
}

class _ClientBucket {
  final int id;
  final String name;
  final String clientType; // 'أفراد' | 'شركة تأمين'
  final List<_Leg> invoices = [];
  final List<_Leg> credits = [];

  double current = 0.0; // 0–30
  double d30 = 0.0; // 31–60
  double d60 = 0.0; // 61–90
  double d90 = 0.0; // 91–120
  double over90 = 0.0; // >120

  _ClientBucket(this.id, this.name, this.clientType);

  Map<String, dynamic> toMap() {
    final total = _round(current + d30 + d60 + d90 + over90);
    return {
      'client_id': id,
      'client_name': name,
      'client_type': clientType,
      'current': _round(current),
      'd30': _round(d30),
      'd60': _round(d60),
      'd90': _round(d90),
      'over90': _round(over90),
      'total_due': total,
    };
  }
}
