import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart'; // تأكد من المسار

class YallaButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isDanger;

  const YallaButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: icon != null ? Icon(icon, size: 20) : const SizedBox(),
      label: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: textColor ?? AppColors.textLight,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ??
            (isDanger ? AppColors.danger : AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 3,
      ),
      onPressed: onPressed,
    );
  }
}
