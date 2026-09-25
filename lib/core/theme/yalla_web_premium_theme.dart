import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

/// Premium web visual system for Yallah Accounts.
///
/// Web-only on purpose: Android/iOS/Windows keep their current presentation
/// until the web pass is accepted.
abstract final class YallaWebPremiumTheme {
  static const Color canvas = Color(0xFFF5F8F5);
  static const Color surface = Colors.white;
  static const Color surfaceSoft = Color(0xFFFAFCFA);
  static const Color border = Color(0xFFDDE8DC);
  static const Color borderStrong = Color(0xFFCFE0CC);
  static const Color text = Color(0xFF344047);
  static const Color muted = Color(0xFF77817D);

  static ThemeData get theme {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEAF8DF),
      onPrimaryContainer: Color(0xFF244414),
      secondary: Color(0xFF5D6B63),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF0F4F0),
      onSecondaryContainer: text,
      surface: surface,
      onSurface: text,
      error: AppColors.danger,
      onError: Colors.white,
    );    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Cairo',
      colorScheme: scheme,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      dividerColor: border,
      canvasColor: canvas,
      cardColor: surface,
      iconTheme: const IconThemeData(color: Color(0xFF68736D), size: 21),
      primaryIconTheme:
          const IconThemeData(color: AppColors.primary, size: 21),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSoft,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        labelStyle: const TextStyle(color: Color(0xFF66716B)),
        prefixIconColor: const Color(0xFF7C8781),
        suffixIconColor: const Color(0xFF7C8781),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),      listTileTheme: ListTileThemeData(
        iconColor: const Color(0xFF69746E),
        textColor: text,
        minTileHeight: 44,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFFF2F6F1),
        selectedColor: const Color(0xFFE8F7DC),
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(Color(0xFFF4F8F3)),
        dividerThickness: 0.7,
        headingTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontSize: 13,
        ),
      ),      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: Color(0xFFE8EFE5),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.white,
        ),
        side: const BorderSide(color: borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : const Color(0xFF8B9690),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : const Color(0xFFDDE4DF),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: text,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.white,
          fontSize: 12,
        ),
      ),      textTheme: base.textTheme.copyWith(
        headlineSmall: const TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: const TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: const TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: const TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontSize: 14,
        ),
        bodyMedium: const TextStyle(
          fontFamily: 'Cairo',
          color: text,
          fontSize: 13,
        ),
      ),
    );
  }
}
