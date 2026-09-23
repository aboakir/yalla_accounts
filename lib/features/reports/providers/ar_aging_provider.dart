// 📁 lib/features/reports/providers/ar_aging_provider.dart
//
// ARAgingProvider — تقادم الذمم من GL v28 (FIFO دقيق)
// - يعتمد فقط على: accounts, gl_entries, gl_lines, clients.
// - يلتقط كل حسابات الذمم: code='1200' أو code LIKE '1200.%' (حسابات العملاء الفرعية).
// - party_type يُعامل بحساسية منخفضة: 'CUSTOMER' أو 'CLIENT'.
// - منهج FIFO: نكوّن فواتير (debit) ونستهلكها بالمدفوعات (credit) من الأقدم.
// - التصنيف حسب تاريخ الفاتورة (تاريخ الـ entry).
//
// ناتج الدالة: List<ARAgingRow> بالحقول:
// clientId, clientName, balance, b0_30, b31_60, b61_90, b90p
//
// ملاحظة: asOf = تاريخ التقادم (نهاية اليوم). افتراضي الآن().

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class ARAgingRow {
  final int clientId;
  final String clientName;
  final double balance;
  final double b0_30;
  final double b31_60;
  final double b61_90;
  final double b90p;
  final double creditBalance;

  ARAgingRow({
    required this.clientId,
    required this.clientName,
    required this.balance,
    required this.b0_30,
    required this.b31_60,
    required this.b61_90,
    required this.b90p,
    this.creditBalance = 0.0,
  });
}

class ARAgingProvider {
  static Future<List<ARAgingRow>> fetch({
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final DatabaseExecutor db = executor ?? await DBService.database;
    final DateTime day = asOf == null
        ? DateTime.now()
        : DateTime(asOf.year, asOf.month, asOf.day);
    final DateTime end = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
    final String nextDayIso =
        DateTime(day.year, day.month, day.day).add(const Duration(days: 1)).toIso8601String();

    // Read the same canonical party projection used by the financial dashboard.
    // The half-open upper bound includes fractional timestamps at the end of day.
    final rows = await db.rawQuery('''
      SELECT
        e.date AS date,
        v.debit AS debit,
        v.credit AS credit,
        COALESCE(pr.legacy_id, CAST(v.legacy_party_id AS TEXT)) AS party_id,
        COALESCE(p.display_name, c.name, 'غير مذكور') AS client_name
      FROM v_party_gl_lines v
      JOIN gl_entries e ON e.id = v.entry_id
      JOIN accounts a ON a.id = v.account_id
      LEFT JOIN parties p ON p.id = v.canonical_party_id
      LEFT JOIN party_roles pr
        ON pr.party_id = v.canonical_party_id AND pr.role = 'CUSTOMER'
      LEFT JOIN clients c ON CAST(c.id AS TEXT) = pr.legacy_id
      WHERE (a.code = '1200' OR a.code LIKE '1200.%')
        AND e.date < ?
        AND v.party_role = 'CUSTOMER'
        AND v.canonical_party_id IS NOT NULL
      ORDER BY e.date ASC, e.id ASC, v.gl_line_id ASC
    ''', [nextDayIso]);

    // 3) بنية FIFO لكل عميل: invoices (debit) / credits
    final Map<int, _ClientBucket> clients = {};
    for (final m in rows) {
      final cid = int.tryParse((m['party_id'] ?? '').toString());
      if (cid == null) continue;

      final cname = (m['client_name'] ?? 'غير مذكور').toString();
      final rec = clients.putIfAbsent(cid, () => _ClientBucket(cid, cname));

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

    // 4) FIFO استهلاك المدفوعات من أقدم الفواتير
    for (final rec in clients.values) {
      rec.invoices.sort((a, b) => a.date.compareTo(b.date));
      rec.credits.sort((a, b) => a.date.compareTo(b.date));

      var creditPool = rec.credits.fold<double>(0, (s, x) => s + x.amount);

      for (final inv in rec.invoices) {
        if (creditPool <= 0) break;
        final take = inv.remaining <= creditPool ? inv.remaining : creditPool;
        inv.remaining = _round(inv.remaining - take);
        creditPool = _round(creditPool - take);
      }
      // An overpayment is still AR truth: it is a customer credit, not zero AR.
      rec.creditBalance = _round(creditPool);

      // 5) وزّع المتبقي حسب عمر الفاتورة حتى asOf
      for (final inv in rec.invoices) {
        final rem = inv.remaining;
        if (rem <= 0) continue;

        final days = end.difference(inv.date).inDays;
        if (days <= 30) {
          rec.b0_30 += rem;
        } else if (days <= 60) {
          rec.b31_60 += rem;
        } else if (days <= 90) {
          rec.b61_90 += rem;
        } else {
          rec.b90p += rem;
        }
      }
    }

    // 6) صياغة الخرج، حذف الصفرية، وترتيب بإجمالي الرصيد نزولًا
    final out = clients.values
        .map((r) => r.toRow())
        .where((r) => r.balance.abs() > 0.000001)
        .toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));

    return out;
  }

  static double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}

// ───────── مساعدات داخلية ─────────

class _Leg {
  final DateTime date;
  final double amount;
  double remaining;
  _Leg({required this.date, required this.amount}) : remaining = amount;
}

class _ClientBucket {
  final int id;
  final String name;
  final List<_Leg> invoices = [];
  final List<_Leg> credits = [];

  double b0_30 = 0.0;
  double b31_60 = 0.0;
  double b61_90 = 0.0;
  double b90p = 0.0;
  double creditBalance = 0.0;

  _ClientBucket(this.id, this.name);

  ARAgingRow toRow() {
    final bal = ARAgingProvider._round(
      b0_30 + b31_60 + b61_90 + b90p - creditBalance,
    );
    return ARAgingRow(
      clientId: id,
      clientName: name,
      balance: bal,
      b0_30: ARAgingProvider._round(b0_30),
      b31_60: ARAgingProvider._round(b31_60),
      b61_90: ARAgingProvider._round(b61_90),
      b90p: ARAgingProvider._round(b90p),
      creditBalance: ARAgingProvider._round(creditBalance),
    );
  }
}
