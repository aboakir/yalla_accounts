import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/utils/storage_helper.dart';

class ThemeSwitcher extends StateNotifier<ThemeMode> {
  ThemeSwitcher({ThemeMode initialMode = ThemeMode.light}) : super(initialMode);

  bool get isDarkMode => state == ThemeMode.dark;

  /// زر "تبديل تلقائي" (Toggle)
  void toggleMode() {
    final isDark = state == ThemeMode.dark;
    state = isDark ? ThemeMode.light : ThemeMode.dark;
    StorageHelper.setBool('is_dark_mode', !isDark);
  }

  /// زر "Switch" مباشر
  void toggleTheme(bool isDark) {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    StorageHelper.setBool('is_dark_mode', isDark);
  }

  void setLightMode() {
    state = ThemeMode.light;
    StorageHelper.setBool('is_dark_mode', false);
  }

  void setDarkMode() {
    state = ThemeMode.dark;
    StorageHelper.setBool('is_dark_mode', true);
  }

  void setSystemMode() {
    state = ThemeMode.system;
    StorageHelper.setBool('is_dark_mode', false); // اختياري
  }
}
