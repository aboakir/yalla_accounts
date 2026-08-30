import 'dart:math' as math;
import 'package:flutter/material.dart';

class MiniLineChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  const MiniLineChart({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 120),
      painter: _MiniLinePainter(values, color),
    );
  }
}

class _MiniLinePainter extends CustomPainter {
  final List<double> v;
  final Color c;
  _MiniLinePainter(this.v, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    final pad = 12.0;
    final area =
        Rect.fromLTWH(pad, pad, size.width - 2 * pad, size.height - 2 * pad);

    final axis = Paint()
      ..color = Colors.black.withOpacity(.08)
      ..strokeWidth = 1;
    canvas.drawLine(area.bottomLeft, area.bottomRight, axis);
    canvas.drawLine(area.bottomLeft, area.topLeft, axis);

    final maxV = v.fold<double>(0, (m, e) => math.max(m, e));
    final safeMax = maxV <= 0 ? 1 : maxV;
    final stepX = area.width / (v.length - 1).clamp(1, 999);

    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = area.left + i * stepX;
      final y = area.bottom - (v[i] / safeMax) * area.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniLinePainter old) =>
      old.v != v || old.c != c;
}
