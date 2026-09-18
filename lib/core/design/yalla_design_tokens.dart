import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

/// Stable visual constants for Yallah Accounts Mobile V2.
///
/// P01 deliberately does not connect these tokens to the existing application
/// theme. Screens adopt them only in their approved implementation phase.
abstract final class YallaColors {
  static const Color brand = AppColors.primary;
  static const Color brandDark = Color(0xFF2F6F38);
  static const Color canvas = Color(0xFFF7F9F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF172019);
  static const Color textMuted = Color(0xFF6D756F);
  static const Color border = Color(0xFFDDE4DF);
  static const Color danger = Color(0xFFD93232);
  static const Color warning = Color(0xFFE69500);
  static const Color info = Color(0xFF2878D4);
  static const Color successSurface = Color(0xFFEAF7E4);
  static const Color dangerSurface = Color(0xFFFCEAEA);
  static const Color warningSurface = Color(0xFFFFF3DB);
  static const Color infoSurface = Color(0xFFE9F2FC);
}

abstract final class YallaSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class YallaRadii {
  static const double compact = 12;
  static const double control = 16;
  static const double card = 20;
  static const double pill = 999;
}

abstract final class YallaDimensions {
  static const double minTouchTarget = 48;
  static const double iconButton = 48;
  static const double fieldHeight = 56;
  static const double primaryButtonHeight = 56;
  static const double bottomNavigationHeight = 72;
}

abstract final class YallaDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}
