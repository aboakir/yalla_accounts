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

  ARAgingRow({
    required this.clientId,
    required this.clientName,
    required this.balance,
    required this.b0_30,
    required this.b31_60,
    required this.b61_90,
    required this.b90p,
  });
}

class ARAgingProvider {
  static Future<List<ARAgingRow>> fetch({DateTime? asOf}) async {
    final Database db = await DBService.database;
    final DateTime end = asOf == null
        ? DateTime.now()
        : DateTime(asOf.year, asOf.month, asOf.day, 23, 59, 59);
    final String asOfIso = end.toIso8601String();

    // 1) جيب ids لكل حسابات الذمم: 1200 والفرعية 1200.*
    final arAccs = await db.rawQuery('''
      SELECT id FROM accounts 
      WHERE code = '1200' OR code LIKE '1200.%'
    ''');
    if (arAccs.isEmpty) return <ARAgingRow>[];

    final accIds = arAccs
        .map((m) => m['id'])
        .where((v) => v != null)
        .map((v) => v is int ? v : int.tryParse(v.toString()) ?? -1)
        .where((v) => v > 0)
        .toList();
    if (accIds.isEmpty) return <ARAgingRow>[];

    // 2) اسحب كل حركات AR حتى asOf، مع ربط اسم العميل (CAST للحاقن)
    //    نفلتر party_type ليتوافق مع قيود GL (CUSTOMER/CLIENT)
    final placeholders = List.filled(accIds.length, '?').join(',');
    final args = <Object?>[...accIds, asOfIso];

    final rows = await db.rawQuery('''
      SELECT
        e.date                         AS date,
        l.debit                        AS debit,
        l.credit                       AS credit,
        UPPER(IFNULL(l.party_type,'')) AS party_type,
        l.party_id                     AS party_id,
        c.name                         AS client_name
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      LEFT JOIN clients c ON c.id = CAST(l.party_id AS INTEGER)
      WHERE l.account_id IN ($placeholders)
        AND e.date <= ?
        AND l.party_id IS NOT NULL
        AND UPPER(IFNULL(l.party_type,'')) IN ('CUSTOMER','CLIENT')
      ORDER BY e.date ASC, e.id ASC, l.id ASC
    ''', args);

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

  _ClientBucket(this.id, this.name);

  ARAgingRow toRow() {
    final bal = ARAgingProvider._round(b0_30 + b31_60 + b61_90 + b90p);
    return ARAgingRow(
      clientId: id,
      clientName: name,
      balance: bal,
      b0_30: ARAgingProvider._round(b0_30),
      b31_60: ARAgingProvider._round(b31_60),
      b61_90: ARAgingProvider._round(b61_90),
      b90p: ARAgingProvider._round(b90p),
    );
  }
}
