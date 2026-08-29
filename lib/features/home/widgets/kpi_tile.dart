// 📁 lib/features/home/widgets/kpi_tile.dart
//
// KpiTile — بطاقة KPI مصغّرة
// --------------------------
// - تعرض عنوان المؤشر + الرقم الحالي + تغير نسبي + رسم sparkline بسيط.
// - تستند إلى بيانات حقيقية فقط من DBService.
// - لا بيانات وهمية، كل ما يُعرض يجب أن يُغذى من DBService أو Provider فعلي.
// - تستخدم في الصفحة الرئيسية لعرض أداء الورشة.
//
// مثال الاستخدام:
//   KpiTile(
//     title: 'إيرادات الشهر',
//     value: 15400.0,
//     change: 12.5,
//     color: Colors.green,
//     sparkline: [1000, 2000, 2500, 4000, 3000, 3500, 4500],
//   );

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class KpiTile extends StatelessWidget {
  final String title;
  final double value;
  final double? change; // نسبة التغير
  final List<double>? sparkline;
  final Color color;
  final VoidCallback? onTap;

  const KpiTile({
    super.key,
    required this.title,
    required this.value,
    this.change,
    this.sparkline,
    this.color = Colors.green,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.##');
    final formattedValue = formatter.format(value);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // الرسم الصغير (Sparkline)
            if (sparkline != null && sparkline!.isNotEmpty)
              SizedBox(
                width: 60,
                height: 30,
                child: CustomPaint(
                  painter: _SparklinePainter(sparkline!, color),
                ),
              )
            else
              SizedBox(width: 60, height: 30),

            const SizedBox(width: 10),

            // النصوص
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formattedValue,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),

            // نسبة التغير
            if (change != null)
              Row(
                children: [
                  Icon(
                    change! >= 0
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: change! >= 0 ? Colors.green : Colors.redAccent,
                    size: 16,
                  ),
                  Text(
                    '${change!.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: change! >= 0 ? Colors.green : Colors.redAccent,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ============== Sparkline Painter ==============
class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final path = Path();
    final minY = data.reduce((a, b) => a < b ? a : b);
    final maxY = data.reduce((a, b) => a > b ? a : b);
    final range = (maxY - minY).abs() < 0.01 ? 1.0 : (maxY - minY);

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minY) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}
