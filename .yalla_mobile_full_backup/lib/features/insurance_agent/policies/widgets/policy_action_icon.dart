// 📁 lib/features/insurance_agent/policies/widgets/policy_action_icon.dart
//
// PolicyActionIcon — CLEAN ICON (NO BOX)
// ✅ بدون مربع
// ✅ بدون خلفية
// ✅ فقط أيقونة + Tooltip
// ✅ Hit area محترمة

import 'package:flutter/material.dart';

class PolicyActionIcon extends StatelessWidget {
  final String tip;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final double size;

  const PolicyActionIcon({
    super.key,
    required this.tip,
    required this.icon,
    required this.onTap,
    this.color,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: color ?? Colors.grey.shade800, size: size),
        splashRadius: 22,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 34,
        ),
      ),
    );
  }
}
