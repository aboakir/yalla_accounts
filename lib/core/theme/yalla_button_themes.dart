import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

abstract final class YallaButtonThemes {
  static final elevated = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.lightGrey,
      disabledForegroundColor: Colors.black54,
    ),
  );

  static final filled = FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.lightGrey,
      disabledForegroundColor: Colors.black54,
    ),
  );

  static final text = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      disabledForegroundColor: Colors.black38,
    ),
  );

  static final outlined = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      disabledForegroundColor: Colors.black38,
      side: const BorderSide(color: AppColors.primary),
    ),
  );
}
