import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/y_glass.dart';

class SalesCard extends StatelessWidget {
  const SalesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return YGlassCard(
      child: DefaultTabController(
        length: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const YSectionTitle('المبيعات', icon: Icons.point_of_sale),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'الفواتير'),
                  Tab(text: 'الربح والخسارة'),
                  Tab(text: 'أحدث الفواتير'),
                  Tab(text: 'فواتير متأخرة'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: const TabBarView(
                children: [
                  _InvoicesChart(),
                  _PnLChart(),
                  _LatestInvoicesList(),
                  _OverdueInvoicesList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === Charts/Lists ===

class _InvoicesChart extends StatelessWidget {
  const _InvoicesChart();

  Future<List<Map<String, Object?>>> _load() async {
    final db = await DBService.database;
    // مجموع يومي آخر 30 يوم
    return db.rawQuery("""
      SELECT DATE(date) d, IFNULL(SUM(total),0) v
      FROM invoices
      WHERE DATE(date)>=DATE('now','-29 day')
      GROUP BY DATE(date)
      ORDER BY DATE(date)
    """);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _load(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final data = snap.data ?? const [];
        if (data.isEmpty) return const Center(child: Text('لا توجد بيانات'));
        // رسم خط بسيط عبر CustomPaint
        return _MiniLine(
            data.map((e) => (e['v'] as num?)?.toDouble() ?? 0).toList(),
            label: 'مجموع الفواتير اليومية');
      },
    );
  }
}

class _PnLChart extends StatelessWidget {
  const _PnLChart();

  Future<List<double>> _load() async {
    final db = await DBService.database;
    final rev = await db.rawQuery("""
      SELECT DATE(e.date) d, IFNULL(SUM(l.credit - l.debit),0) v
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code LIKE '4%' AND DATE(e.date)>=DATE('now','-29 day')
      GROUP BY DATE(e.date) ORDER BY DATE(e.date)
    """);
    final exp = await db.rawQuery("""
      SELECT DATE(e.date) d, IFNULL(SUM(l.debit - l.credit),0) v
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE a.code LIKE '5%' AND DATE(e.date)>=DATE('now','-29 day')
      GROUP BY DATE(e.date) ORDER BY DATE(e.date)
    """);

    // دمج حسب اليوم: صافي = الإيراد - المصروف
    final map = <String, double>{};
    for (final r in rev) {
      map[r['d'] as String] = ((r['v'] as num?) ?? 0).toDouble();
    }
    for (final x in exp) {
      final d = x['d'] as String;
      final v = ((x['v'] as num?) ?? 0).toDouble();
      map[d] = (map[d] ?? 0) - v;
    }

    // تأكد من 30 نقطة
    final out = List<double>.filled(30, 0);
    for (final e in map.entries) {
      final diff =
          DateTime.now().difference(DateTime.parse(e.key)).inDays.clamp(0, 29);
      out[29 - diff] = e.value;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<double>>(
      future: _load(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final data = snap.data ?? const [];
        if (data.every((v) => v == 0)) {
          return const Center(child: Text('لا توجد بيانات'));
        }
        return _MiniLine(data, label: 'صافي الربح/الخسارة');
      },
    );
  }
}

class _LatestInvoicesList extends StatelessWidget {
  const _LatestInvoicesList();

  Future<List<Map<String, Object?>>> _load() async {
    final db = await DBService.database;
    return db.rawQuery("""
      SELECT id, date, total, client_id
      FROM invoices
      ORDER BY datetime(date) DESC
      LIMIT 8
    """);
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0.##');
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _load(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) return const Center(child: Text('لا توجد بيانات'));
        return ListView.separated(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[i];
            return ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text('فاتورة ${r['id']}'),
              subtitle: Text('${r['date']}'),
              trailing: Text(nf.format((r['total'] as num?) ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () =>
                  Navigator.pushNamed(context, '/finance/invoices/${r['id']}'),
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 8),
        );
      },
    );
  }
}

class _OverdueInvoicesList extends StatelessWidget {
  const _OverdueInvoicesList();

  Future<List<Map<String, Object?>>> _load() async {
    final db = await DBService.database;
    // متأخرة: حالة ليست "Paid" وتاريخ أقدم من 30 يوم
    return db.rawQuery("""
      SELECT id, date, total, client_id, status
      FROM invoices
      WHERE (status IS NULL OR LOWER(status) NOT IN ('paid','مدفوعة'))
        AND DATE(date) < DATE('now','-30 day')
      ORDER BY DATE(date)
      LIMIT 12
    """);
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0.##');
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _load(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) return const Center(child: Text('لا توجد بيانات'));
        return ListView.separated(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[i];
            return ListTile(
              leading:
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              title: Text('فاتورة ${r['id']}'),
              subtitle: Text('${r['date']} • ${r['status'] ?? 'غير مدفوعة'}'),
              trailing: Text(nf.format((r['total'] as num?) ?? 0),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.orange)),
              onTap: () =>
                  Navigator.pushNamed(context, '/finance/invoices/${r['id']}'),
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 8),
        );
      },
    );
  }
}

// رسّام خط صغير
class _MiniLine extends StatelessWidget {
  final List<double> data;
  final String label;
  const _MiniLine(this.data, {required this.label});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MiniLinePainter(data),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.topRight,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      ),
    );
  }
}

class _MiniLinePainter extends CustomPainter {
  final List<double> d;
  _MiniLinePainter(this.d);

  @override
  void paint(Canvas c, Size s) {
    if (d.isEmpty) return;
    final area = Rect.fromLTWH(8, 24, s.width - 16, s.height - 32);
    final axis = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..strokeWidth = 1;
    c.drawLine(area.bottomLeft, area.bottomRight, axis);
    c.drawLine(area.bottomLeft, area.topLeft, axis);

    final maxV = d
        .fold<double>(0, (m, v) => v.abs() > m ? v.abs() : m)
        .clamp(1, double.infinity);
    final stepX = area.width / (d.length - 1);

    final p = Path();
    for (var i = 0; i < d.length; i++) {
      final x = area.left + i * stepX;
      final y = area.center.dy - (d[i] / maxV) * (area.height / 2);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    final line = Paint()
      ..color = Colors.indigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawPath(p, line);
  }

  @override
  bool shouldRepaint(covariant _MiniLinePainter old) => old.d != d;
}
