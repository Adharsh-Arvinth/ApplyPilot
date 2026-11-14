import 'dart:ui';
import 'package:flutter/material.dart';

class AppColors {
  // Apple Music Signature Vibrant Palette
  static const Color appleMusicRose = Color(0xFFFA243C);
  static const Color appleCrimson = Color(0xFFFA243C);
  static const Color appleMusicPink = Color(0xFFFC3C44);
  static const Color appleMusicGradientEnd = Color(0xFFFF2D55);
  static const Color iosGreen = Color(0xFF30D158);
  static const Color iosRed = Color(0xFFFF453A);
  static const Color iosOrange = Color(0xFFFF9F0A);
  static const Color iosBlue = Color(0xFF0A84FF);
  static const Color iosPurple = Color(0xFFBF5AF2);

  // Light Theme Palette (Clean Apple Music / iOS Grouped)
  static const Color canvasLight = Color(0xFFF2F2F7);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSubtleLight = Color(0xFFE5E5EA);
  static const Color borderHairlineLight = Color(0xFFD1D1D6);
  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textSecondaryLight = Color(0xFF6C6C70);
  static const Color textMutedLight = Color(0xFF8E8E93);
  static const Color accentLight = Color(0xFFFA243C);
  static const Color accentOnAccentLight = Color(0xFFFFFFFF);
  static const Color successLight = Color(0xFF34C759);
  static const Color warningLight = Color(0xFFFF9500);
  static const Color blockedLight = Color(0xFFFF3B30);
  static const Color purpleLight = Color(0xFFAF52DE);
  static const Color blueLight = Color(0xFF007AFF);

  // Dark Theme Palette (Pure OLED Black & Apple Music Glass)
  static const Color canvasDark = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color surfaceSubtleDark = Color(0xFF2C2C2E);
  static const Color borderHairlineDark = Color(0xFF38383A);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFF8E8E93);
  static const Color textMutedDark = Color(0xFF636366);
  static const Color accentDark = Color(0xFFFA243C);
  static const Color accentOnAccentDark = Color(0xFFFFFFFF);
  static const Color successDark = Color(0xFF30D158);
  static const Color warningDark = Color(0xFFFF9F0A);
  static const Color blockedDark = Color(0xFFFF453A);
  static const Color purpleDark = Color(0xFFBF5AF2);
  static const Color blueDark = Color(0xFF0A84FF);
}

class AppSpacing {
  static const double s4 = 4.0;
  static const double s6 = 6.0;
  static const double s8 = 8.0;
  static const double s10 = 10.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double s40 = 40.0;
}

class AppRadii {
  static const double card = 18.0;
  static const double control = 12.0;
  static const double badge = 6.0;
  static const double pill = 100.0;
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
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceLight,
        foregroundColor: AppColors.textPrimaryLight,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.8,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
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
          fontWeight: FontWeight.w500,
          color: AppColors.textMutedLight,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.borderHairlineLight, width: 0.8),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderHairlineLight,
        thickness: 0.8,
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
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvasDark,
        foregroundColor: AppColors.textPrimaryDark,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryDark,
          letterSpacing: -0.8,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryDark,
          letterSpacing: -0.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
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
          fontWeight: FontWeight.w500,
          color: AppColors.textMutedDark,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.borderHairlineDark, width: 0.8),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderHairlineDark,
        thickness: 0.8,
      ),
    );
  }
}
