import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/theme/yalla_button_themes.dart';

abstract final class YallaMobileTheme {
  static const double drawerMinWidth = 260;
  static const double drawerMaxWidth = 300;
  static const double drawerWidthFraction = 0.82;

  static double drawerWidthFor(double viewportWidth) =>
      (viewportWidth * drawerWidthFraction)
          .clamp(drawerMinWidth, drawerMaxWidth)
          .toDouble();

  static ThemeData from(
    ThemeData base, {
    double? viewportWidth,
  }) =>
      base.copyWith(
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            side: BorderSide(color: Color(0xFFE2E8E4)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDDE4E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: YallaButtonThemes.filled.style!.copyWith(
            minimumSize: const MaterialStatePropertyAll(Size(48, 50)),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: YallaButtonThemes.elevated.style!.copyWith(
            minimumSize: const MaterialStatePropertyAll(Size(48, 50)),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        textButtonTheme: YallaButtonThemes.text,
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: YallaButtonThemes.outlined.style!.copyWith(
            minimumSize: const MaterialStatePropertyAll(Size(48, 48)),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 68,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.lightGreen,
        ),
        drawerTheme: DrawerThemeData(
          width: viewportWidth == null
              ? drawerMaxWidth
              : drawerWidthFor(viewportWidth),
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          showDragHandle: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      );
}
