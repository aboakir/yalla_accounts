import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class YGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double blur;
  final double opacity;
  final Color? borderColor;

  const YGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.radius = 16,
    this.blur = 18,
    this.opacity = 0.80,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface.withOpacity(opacity);
    final br = borderColor ?? Theme.of(context).primaryColor.withOpacity(0.10);
    final r = BorderRadius.circular(radius);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bg,
            bg.withOpacity(opacity - 0.15),
          ],
        ),
        border: Border.all(color: br),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Material(
            // الحل الأساسي للمشكلة
            type: MaterialType.transparency,
            borderRadius: r,
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class YSectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;
  const YSectionTitle(this.title, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).primaryColor;
    return AdaptiveRow(
      children: [
        if (icon != null)
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: c),
          ),
        if (icon != null) const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
