// 📁 lib/shared/widgets/dashboard/summary_card.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  const SummaryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = color ?? AppColors.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 300;

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isDark ? Colors.grey[850] : Colors.white.withOpacity(0.7),
              border: Border.all(color: cardColor.withOpacity(0.35), width: 1),
              boxShadow: [
                BoxShadow(
                  color: cardColor.withOpacity(isDark ? 0.08 : 0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: AdaptiveRow(
              children: [
                CircleAvatar(
                  radius: isWide ? 28 : 24,
                  backgroundColor: cardColor,
                  child: Icon(
                    icon,
                    size: isWide ? 24 : 20,
                    color: Colors.white,
                    semanticLabel: title,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: isWide ? 16 : 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: Text(
                          value,
                          key: ValueKey(value),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: isWide ? 24 : 18,
                            fontWeight: FontWeight.bold,
                            color: cardColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
