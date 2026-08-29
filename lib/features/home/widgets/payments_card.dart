import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/y_glass.dart';

class PaymentsCard extends StatelessWidget {
  const PaymentsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return YGlassCard(
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const YSectionTitle('المدفوعات', icon: Icons.payments),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: const TabBar(
                isScrollable: true,
                tabs: [Tab(text: 'إحصائيات'), Tab(text: 'أحدث المدفوعات')],
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(
              height: 200,
              child:
                  TabBarView(children: [_PaymentsStats(), _LatestPaysList()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentsStats extends StatelessWidget {
  const _PaymentsStats();

  Future<List<double>> _load() async {
    final db = await DBService.database;
    final rows = await db.rawQuery("""
      SELECT DATE(date) d, IFNULL(SUM(amount),0) v
      FROM payments
      WHERE DATE(date)>=DATE('now','-29 day')
      GROUP BY DATE(date) ORDER BY DATE(date)
    """);
    final out = List<double>.filled(30, 0);
    for (final r in rows) {
      final d = r['d'] as String;
      final v = ((r['v'] as num?) ?? 0).toDouble();
      final diff =
          DateTime.now().difference(DateTime.parse(d)).inDays.clamp(0, 29);
      out[29 - diff] = v;
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
        return CustomPaint(painter: _MiniLinePainter(data));
      },
    );
  }
}

class _LatestPaysList extends StatelessWidget {
  const _LatestPaysList();

  Future<List<Map<String, Object?>>> _load() async {
    final db = await DBService.database;
    return db.rawQuery("""
      SELECT id, amount, method, date
      FROM payments
      ORDER BY datetime(date) DESC
      LIMIT 10
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
              leading: const Icon(Icons.payments),
              title: Text(nf.format((r['amount'] as num?) ?? 0)),
              subtitle: Text('${r['date']} • ${r['method'] ?? ''}'),
              onTap: () =>
                  Navigator.pushNamed(context, '/finance/payments/${r['id']}'),
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 8),
        );
      },
    );
  }
}

// نفس الرسّام من sales_card.dart
class _MiniLinePainter extends CustomPainter {
  final List<double> d;
  _MiniLinePainter(this.d);
  @override
  void paint(Canvas c, Size s) {
    if (d.isEmpty) return;
    final area = Rect.fromLTWH(8, 8, s.width - 16, s.height - 16);
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
      final y = area.bottom - (d[i] / maxV) * area.height;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    final line = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawPath(p, line);
  }

  @override
  bool shouldRepaint(covariant _MiniLinePainter old) => old.d != d;
}
