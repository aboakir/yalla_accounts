// 📁 lib/features/home/widgets/analytics_charts.dart
//
// AnalyticsCharts — مخططات تحليلية خفيفة بدون مكتبات خارجية
// DB فقط، بدون بيانات وهمية. مع حراس try/catch لمنع أي تعليق.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class AnalyticsCharts extends StatefulWidget {
  const AnalyticsCharts({super.key});
  @override
  State<AnalyticsCharts> createState() => _AnalyticsChartsState();
}

class _AnalyticsChartsState extends State<AnalyticsCharts> {
  bool _loading = true;

  // 1) آخر 30 يوم: revenue vs expense
  late List<_Point> revenue30; // date,value
  late List<_Point> expense30;

  // 2) توزيع الإيرادات
  late List<_Slice> revenueDist;

  // 3) تدفق نقدي أسبوعي مكدّس
  late List<_WeekBar> cashWeekly;

  // رموز الحسابات لديك
  final String revenuePrefix = '4';
  final String expensePrefix = '5';
  final List<String> cashAccounts = const ['1000', '1010'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Database db = await DBService.database;
    final now = DateTime.now();
    final start30 = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 29));
    final fmt = DateFormat('yyyy-MM-dd');

    // قيَم افتراضية آمنة
    revenue30 =
        List.generate(30, (i) => _Point(start30.add(Duration(days: i)), 0));
    expense30 =
        List.generate(30, (i) => _Point(start30.add(Duration(days: i)), 0));
    revenueDist = const [];
    cashWeekly = const [];

    try {
      // ===== 1) سلسلة يومية للإيراد والمصروف =====
      final Map<String, double> revMap = {};
      final Map<String, double> expMap = {};

      final revRows = await db.rawQuery('''
        SELECT date, IFNULL(SUM(credit - debit),0) AS v
        FROM gl_lines
        WHERE account_code LIKE ?
          AND date BETWEEN ? AND ?
        GROUP BY date
      ''', ['$revenuePrefix%', fmt.format(start30), fmt.format(now)]);
      for (final r in revRows) {
        final k = (r['date'] ?? '').toString();
        revMap[k] = ((r['v'] ?? 0) as num).toDouble();
      }

      final expRows = await db.rawQuery('''
        SELECT date, IFNULL(SUM(debit - credit),0) AS v
        FROM gl_lines
        WHERE account_code LIKE ?
          AND date BETWEEN ? AND ?
        GROUP BY date
      ''', ['$expensePrefix%', fmt.format(start30), fmt.format(now)]);
      for (final r in expRows) {
        final k = (r['date'] ?? '').toString();
        expMap[k] = ((r['v'] ?? 0) as num).toDouble();
      }

      revenue30 = [];
      expense30 = [];
      for (int i = 0; i < 30; i++) {
        final d = start30.add(Duration(days: i));
        final key = fmt.format(d);
        revenue30.add(_Point(d, revMap[key] ?? 0));
        expense30.add(_Point(d, expMap[key] ?? 0));
      }

      // ===== 2) توزيع الإيرادات حسب الفئة =====
      final distRows = await db.rawQuery('''
        SELECT account_code, IFNULL(SUM(credit - debit),0) AS v
        FROM gl_lines
        WHERE account_code LIKE ?
          AND date BETWEEN ? AND ?
        GROUP BY account_code
        HAVING SUM(credit - debit) > 0         -- لا تستخدم alias في HAVING
        ORDER BY v DESC
      ''', ['$revenuePrefix%', fmt.format(start30), fmt.format(now)]);

      final Map<String, double> grouped = {};
      for (final r in distRows) {
        final code = (r['account_code'] ?? '').toString();
        final v = ((r['v'] ?? 0) as num).toDouble();
        if (v <= 0) continue;
        final group = code.length >= 3 ? code.substring(0, 3) : code;
        grouped[group] = (grouped[group] ?? 0) + v;
      }
      final sorted = grouped.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted.take(4).toList();
      final otherSum = sorted.skip(4).fold<double>(0, (p, e) => p + e.value);
      revenueDist = [
        ...top.map((e) => _Slice(label: e.key, value: e.value)),
        if (otherSum > 0) const _Slice(label: 'أخرى', value: 0) // placeholder
      ];
      if (otherSum > 0) {
        revenueDist = [
          ...top.map((e) => _Slice(label: e.key, value: e.value)),
          _Slice(label: 'أخرى', value: otherSum),
        ];
      }

      // ===== 3) تدفق نقدي أسبوعي (8 أسابيع) =====
      final List<_WeekBar> tempBars = [];
      DateTime weekEnd = DateTime(now.year, now.month, now.day);
      for (int w = 0; w < 8; w++) {
        final weekStart = weekEnd.subtract(const Duration(days: 6));
        final rows = await db.rawQuery('''
          SELECT 
            IFNULL(SUM(debit),0) AS d,
            IFNULL(SUM(credit),0) AS c
          FROM gl_lines
          WHERE account_code IN (${List.filled(cashAccounts.length, '?').join(',')})
            AND date BETWEEN ? AND ?
        ''', [
          ...cashAccounts,
          fmt.format(weekStart),
          fmt.format(weekEnd),
        ]);
        final d = ((rows.first['d'] ?? 0) as num).toDouble();
        final c = ((rows.first['c'] ?? 0) as num).toDouble();
        final label =
            '${DateFormat('MM/dd').format(weekStart)}–${DateFormat('MM/dd').format(weekEnd)}';
        tempBars.add(_WeekBar(label: label, inflow: d, outflow: c));
        weekEnd = weekStart.subtract(const Duration(days: 1));
      }
      cashWeekly = tempBars.reversed.toList();
    } catch (_) {
      // فشل آمن: تترك القيم الافتراضية وتُكمّل
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ChartsSkeleton();

    return Column(
      children: [
        _ChartCard(
          title: 'إيرادات مقابل مصروفات (آخر 30 يومًا)',
          child: SizedBox(
            height: 220,
            child: _LineChart(
              series: [
                _LineSeries('الإيرادات', revenue30, Colors.green),
                _LineSeries('المصروفات', expense30, Colors.redAccent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ChartCard(
                title: 'توزيع الإيرادات',
                child: SizedBox(
                    height: 240, child: _DonutChart(slices: revenueDist)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ChartCard(
                title: 'التدفق النقدي الأسبوعي',
                child: SizedBox(
                    height: 240, child: _StackedBars(bars: cashWeekly)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ========================= UI Components =========================

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

// ========================= Line Chart =========================

class _Point {
  final DateTime x;
  final double y;
  const _Point(this.x, this.y);
}

class _LineSeries {
  final String name;
  final List<_Point> points;
  final Color color;
  const _LineSeries(this.name, this.points, this.color);
}

class _LineChart extends StatelessWidget {
  final List<_LineSeries> series;
  const _LineChart({required this.series});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LinePainter(series), child: Container());
  }
}

class _LinePainter extends CustomPainter {
  final List<_LineSeries> series;
  const _LinePainter(this.series);

  static const double pad = 28;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final rect = Rect.fromLTWH(pad, 8, size.width - pad - 8, size.height - 32);

    final axisPaint = Paint()
      ..color = Colors.grey.withOpacity(0.25)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(rect.left, rect.bottom),
        Offset(rect.right, rect.bottom), axisPaint);
    canvas.drawLine(
        Offset(rect.left, rect.top), Offset(rect.left, rect.bottom), axisPaint);

    DateTime minX = series.first.points.first.x;
    DateTime maxX = series.first.points.last.x;
    double minY = 0, maxY = 0;
    for (final s in series) {
      for (final p in s.points) {
        if (p.x.isBefore(minX)) minX = p.x;
        if (p.x.isAfter(maxX)) maxX = p.x;
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
    }
    if ((maxY - minY).abs() < 1e-6) maxY = minY + 1;

    double mapX(DateTime d) {
      final t = d.millisecondsSinceEpoch.toDouble();
      final t0 = minX.millisecondsSinceEpoch.toDouble();
      final t1 = maxX.millisecondsSinceEpoch.toDouble();
      return rect.left + (t - t0) / (t1 - t0) * rect.width;
    }

    double mapY(double v) {
      return rect.bottom - (v - minY) / (maxY - minY) * rect.height;
    }

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = rect.top + i * rect.height / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    for (final s in series) {
      final p = Path();
      var first = true;
      for (final pt in s.points) {
        final x = mapX(pt.x);
        final y = mapY(pt.y);
        if (first) {
          p.moveTo(x, y);
          first = false;
        } else {
          p.lineTo(x, y);
        }
      }
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = true;
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) => true;
}

// ========================= Donut Chart =========================

class _Slice {
  final String label;
  final double value;
  const _Slice({required this.label, required this.value});
}

class _DonutChart extends StatelessWidget {
  final List<_Slice> slices;
  const _DonutChart({required this.slices});

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (p, s) => p + s.value);
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(size: Size.infinite, painter: _DonutPainter(slices)),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('الإجمالي', style: TextStyle(color: Colors.grey)),
            Text(
              NumberFormat('#,##0.##').format(total),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: slices.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final c = _palette[i % _palette.length];
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 10, color: c),
                      const SizedBox(width: 4),
                      Text(slices[i].label,
                          style: const TextStyle(fontSize: 12)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

const List<Color> _palette = [
  Colors.green,
  Colors.blueGrey,
  Colors.orange,
  Colors.teal,
  Colors.purple,
  Colors.indigo,
  Colors.brown,
];

class _DonutPainter extends CustomPainter {
  final List<_Slice> slices;
  const _DonutPainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;
    final total = slices.fold<double>(0, (p, s) => p + s.value);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2.6;
    double startAngle = -math.pi / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.46
      ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = (s.value / total) * 2 * math.pi;
      paint.color = _palette[i % _palette.length].withOpacity(0.9);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

// ========================= Stacked Bars =========================

class _WeekBar {
  final String label;
  final double inflow; // debit
  final double outflow; // credit
  const _WeekBar(
      {required this.label, required this.inflow, required this.outflow});
}

class _StackedBars extends StatelessWidget {
  final List<_WeekBar> bars;
  const _StackedBars({required this.bars});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _StackedBarsPainter(bars), child: Container());
  }
}

class _StackedBarsPainter extends CustomPainter {
  final List<_WeekBar> bars;
  const _StackedBarsPainter(this.bars);

  static const double pad = 28;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final rect = Rect.fromLTWH(pad, 8, size.width - pad - 8, size.height - 32);

    final axisPaint = Paint()
      ..color = Colors.grey.withOpacity(0.25)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(rect.left, rect.bottom),
        Offset(rect.right, rect.bottom), axisPaint);
    canvas.drawLine(
        Offset(rect.left, rect.top), Offset(rect.left, rect.bottom), axisPaint);

    double maxStack = 0;
    for (final b in bars) {
      maxStack = math.max(maxStack, b.inflow + b.outflow);
    }
    if (maxStack < 1e-6) maxStack = 1;

    final barWidth = rect.width / (bars.length * 1.6);
    final gap = barWidth * 0.6;

    final inflowPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;
    final outflowPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    for (int i = 0; i < bars.length; i++) {
      final b = bars[i];
      final x = rect.left + i * (barWidth + gap);

      final hIn = (b.inflow / maxStack) * rect.height;
      final hOut = (b.outflow / maxStack) * rect.height;

      final rIn = Rect.fromLTWH(x, rect.bottom - hIn, barWidth, hIn);
      final rOut = Rect.fromLTWH(x, rect.bottom - hIn - hOut, barWidth, hOut);

      canvas.drawRect(rIn, inflowPaint);
      canvas.drawRect(rOut, outflowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StackedBarsPainter oldDelegate) => true;
}

// ========================= Skeleton =========================

class _ChartsSkeleton extends StatelessWidget {
  const _ChartsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box({double h = 180}) => Container(
          height: h,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
        );

    return Column(
      children: [
        box(h: 220),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: box(h: 240)),
            const SizedBox(width: 16),
            Expanded(child: box(h: 240)),
          ],
        ),
      ],
    );
  }
}
