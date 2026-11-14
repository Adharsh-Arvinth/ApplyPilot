import 'dart:ui';
import 'package:flutter/material.dart';

class AppColors {
  // Light Theme Palette (Warm Ivory & British Racing Green)
  static const Color canvasLight = Color(0xFFFAFAF7);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSubtleLight = Color(0xFFF4F4F0);
  static const Color borderHairlineLight = Color(0xFFE7E6E0);
  static const Color textPrimaryLight = Color(0xFF111111);
  static const Color textSecondaryLight = Color(0xFF555550);
  static const Color textMutedLight = Color(0xFF8E8E88);
  static const Color accentLight = Color(0xFF1B4332);
  static const Color accentOnAccentLight = Color(0xFFFFFFFF);
  static const Color warningLight = Color(0xFF7A5C2E);
  static const Color blockedLight = Color(0xFF8A2828);

  // Dark Theme Palette (Graphite & Muted Jade)
  static const Color canvasDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1C1C1C);
  static const Color surfaceSubtleDark = Color(0xFF242424);
  static const Color borderHairlineDark = Color(0xFF2D2D2D);
  static const Color textPrimaryDark = Color(0xFFF0F0EE);
  static const Color textSecondaryDark = Color(0xFF9E9E98);
  static const Color textMutedDark = Color(0xFF666662);
  static const Color accentDark = Color(0xFF52B788);
  static const Color accentOnAccentDark = Color(0xFF111111);
  static const Color warningDark = Color(0xFFDDA15E);
  static const Color blockedDark = Color(0xFFE57373);
}

class AppSpacing {
  static const double s4 = 4.0;
  static const double s6 = 6.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double s40 = 40.0;
}

class AppRadii {
  static const double card = 16.0;
  static const double control = 8.0;
  static const double badge = 4.0;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.canvasLight,
      colorScheme: const ColorScheme.light(
        surface: AppColors.surfaceLight,
        primary: AppColors.accentLight,
        onPrimary: AppColors.accentOnAccentLight,
        error: AppColors.blockedLight,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryLight,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryLight,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryLight,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimaryLight,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondaryLight,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textMutedLight,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.borderHairlineLight, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderHairlineLight,
        thickness: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.canvasDark,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surfaceDark,
        primary: AppColors.accentDark,
        onPrimary: AppColors.accentOnAccentDark,
        error: AppColors.blockedDark,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryDark,
          letterSpacing: -0.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryDark,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryDark,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryDark,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimaryDark,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondaryDark,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textMutedDark,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.borderHairlineDark, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderHairlineDark,
        thickness: 1,
      ),
    );
  }
}
