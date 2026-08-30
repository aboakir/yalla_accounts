// 📁 lib/features/repairs/widgets/repair_stats.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

typedef StatusTapCallback = void Function(String status);

class RepairStats extends StatelessWidget {
  final List<Repair> repairs;
  final StatusTapCallback? onStatusTap;

  const RepairStats({
    super.key,
    required this.repairs,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = repairs.length;
    final paid =
        repairs.where((r) => (r.paymentStatus ?? '').trim() == 'مسدد').length;
    final partial = repairs
        .where((r) => (r.paymentStatus ?? '').trim() == 'مسدد جزئي')
        .length;
    final unpaid = repairs
        .where((r) => (r.paymentStatus ?? '').trim() == 'غير مسدد')
        .length;

    final stats = [
      _StatData('الكل', total, Colors.blueGrey, Icons.list),
      _StatData('مسدد', paid, AppColors.success, Icons.check_circle),
      _StatData('مسدد جزئي', partial, AppColors.warning, Icons.timelapse),
      _StatData('غير مسدد', unpaid, AppColors.danger, Icons.cancel),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceAround,
            children: stats.map((stat) {
              final percent = total == 0 ? 0.0 : stat.count / total;
              return _AnimatedGlassCard(
                data: stat,
                percent: percent,
                isDark: isDark,
                width: isWide
                    ? (constraints.maxWidth - 36) / 4
                    : constraints.maxWidth - 24,
                onTap: () => onStatusTap?.call(stat.title),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _StatData {
  final String title;
  final int count;
  final Color color;
  final IconData icon;

  _StatData(this.title, this.count, this.color, this.icon);
}

class _AnimatedGlassCard extends StatelessWidget {
  final _StatData data;
  final double percent;
  final bool isDark;
  final double width;
  final VoidCallback onTap;

  const _AnimatedGlassCard({
    required this.data,
    required this.percent,
    required this.isDark,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? Colors.white12 : Colors.white.withOpacity(0.6);
    final textColor = isDark ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: data.color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: data.color.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          backgroundBlendMode: BlendMode.overlay,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(data.icon, color: data.color, size: 28),
            const SizedBox(height: 8),
            Text(
              '${data.count}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: data.color,
              ),
            ),
            Text(
              data.title,
              style: TextStyle(fontSize: 14, color: textColor),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: percent),
                duration: const Duration(milliseconds: 700),
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: Colors.grey.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(data.color),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(percent * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                color: textColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
