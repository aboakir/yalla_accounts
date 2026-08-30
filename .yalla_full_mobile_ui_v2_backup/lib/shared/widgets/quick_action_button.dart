// 📁 lib/shared/widgets/dashboard/quick_action_button.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class QuickActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String route;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.route,
  });

  @override
  State<QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<QuickActionButton> {
  bool _isPressed = false;

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
  }

  Future<void> _navigate(BuildContext context) async {
    try {
      await Navigator.pushNamed(context, widget.route);
    } on FlutterError catch (_) {
      // حماية من مسار غير معرّف
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('المسار غير متاح حالياً: ${widget.route}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor =
        isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.6);
    final borderColor = AppColors.primary.withOpacity(0.25);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () => _navigate(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: _isPressed ? 130 : 140,
        height: _isPressed ? 130 : 140,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: _isPressed
              ? []
              : [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: 36,
              color: AppColors.primary,
              semanticLabel: widget.label,
            ),
            const SizedBox(height: 10),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
