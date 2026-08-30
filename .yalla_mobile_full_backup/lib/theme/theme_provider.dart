import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/utils/storage_helper.dart';

final themeSwitcherProvider = StateNotifierProvider<ThemeSwitcher, ThemeMode>(
  (ref) {
    final isDark = StorageHelper.getBool('is_dark_mode');
    return ThemeSwitcher(
        initialMode: isDark ? ThemeMode.dark : ThemeMode.light);
  },
);

class ThemeSwitcher extends StateNotifier<ThemeMode> {
  ThemeSwitcher({ThemeMode initialMode = ThemeMode.light}) : super(initialMode);

  void toggleMode() {
    final isDark = state == ThemeMode.dark;
    state = isDark ? ThemeMode.light : ThemeMode.dark;
    StorageHelper.setBool('is_dark_mode', !isDark);
  }

  void setLightMode() {
    state = ThemeMode.light;
    StorageHelper.setBool('is_dark_mode', false);
  }

  void setDarkMode() {
    state = ThemeMode.dark;
    StorageHelper.setBool('is_dark_mode', true);
  }
}
