import 'dart:ui';
import 'package:flutter/material.dart';

class AppColors {
  // ApplyPilot Signature Editorial Palette: British Racing Green, Warm Ivory & Muted Brass
  static const Color warmIvory = Color(0xFFFAFAF7);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color racingGreen = Color(0xFF1B4332);
  static const Color racingGreenLight = Color(0xFF2D6A4F);
  static const Color racingGreenVibrant = Color(0xFF40916C);
  static const Color racingGreenSubtle = Color(0xFFD8F3DC);
  static const Color mutedBrass = Color(0xFFC5A880);
  static const Color mutedBrassWarm = Color(0xFFB59A57);
  static const Color brassGlow = Color(0xFFD4AF37);

  // Status & Utility Colors
  static const Color forestInk = Color(0xFF14221A);
  static const Color charcoal = Color(0xFF2B3A32);
  static const Color mutedGray = Color(0xFF5C6B63);
  static const Color subtleGray = Color(0xFF88968F);
  static const Color hairlineBorder = Color(0xFFE5E3DC);

  // Light Theme Palette (Warm Ivory & British Racing Green Editorial)
  static const Color canvasLight = Color(0xFFFAFAF7);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSubtleLight = Color(0xFFF2F1EC);
  static const Color borderHairlineLight = Color(0xFFE5E3DC);
  static const Color textPrimaryLight = Color(0xFF14221A);
  static const Color textSecondaryLight = Color(0xFF5C6B63);
  static const Color textMutedLight = Color(0xFF88968F);
  static const Color accentLight = Color(0xFF1B4332);
  static const Color accentOnAccentLight = Color(0xFFFFFFFF);
  static const Color brassLight = Color(0xFFC5A880);
  static const Color successLight = Color(0xFF2D6A4F);
  static const Color warningLight = Color(0xFFD4A373);
  static const Color errorLight = Color(0xFFBA1A1A);
  static const Color blueLight = Color(0xFF1D4E89);

  // Dark Theme Palette (Deep Forest Slate / Obsidian & Racing Green Glow)
  static const Color canvasDark = Color(0xFF0D1912);
  static const Color surfaceDark = Color(0xFF14251B);
  static const Color surfaceSubtleDark = Color(0xFF1A2F23);
  static const Color borderHairlineDark = Color(0xFF253F30);
  static const Color textPrimaryDark = Color(0xFFFAFAF7);
  static const Color textSecondaryDark = Color(0xFFA3B8AD);
  static const Color textMutedDark = Color(0xFF6C8074);
  static const Color accentDark = Color(0xFF40916C);
  static const Color accentOnAccentDark = Color(0xFFFFFFFF);
  static const Color brassDark = Color(0xFFD4AF37);
  static const Color successDark = Color(0xFF52B788);
  static const Color warningDark = Color(0xFFE9C46A);
  static const Color errorDark = Color(0xFFFF6B6B);
  static const Color blueDark = Color(0xFF64DFDF);

  // Semantic Colorful Palette
  // Emerald: Successful applications & positive progress
  static const Color emeraldLight = Color(0xFF2D6A4F);
  static const Color emeraldDark = Color(0xFF52B788);
  // Blue: Job discovery & general information
  static const Color semanticBlueLight = Color(0xFF1D4E89);
  static const Color semanticBlueDark = Color(0xFF4895EF);
  // Violet: AI operations & resume intelligence
  static const Color violetLight = Color(0xFF6A4C93);
  static const Color violetDark = Color(0xFF9D4EDD);
  // Amber: Pending approvals & attention required
  static const Color amberLight = Color(0xFFD4A373);
  static const Color amberDark = Color(0xFFF4A261);
  // Coral: Errors, failed applications & warnings
  static const Color coralLight = Color(0xFFE76F51);
  static const Color coralDark = Color(0xFFE63946);
  // Teal: Interviews & career milestones
  static const Color tealLight = Color(0xFF0081A7);
  static const Color tealDark = Color(0xFF2A9D8F);

  static Color getSemanticColor(String type, bool isDark) {
    switch (type.toLowerCase()) {
      case 'emerald':
      case 'success':
        return isDark ? emeraldDark : emeraldLight;
      case 'blue':
      case 'discovery':
        return isDark ? semanticBlueDark : semanticBlueLight;
      case 'violet':
      case 'ai':
        return isDark ? violetDark : violetLight;
      case 'amber':
      case 'pending':
        return isDark ? amberDark : amberLight;
      case 'coral':
      case 'error':
        return isDark ? coralDark : coralLight;
      case 'teal':
      case 'interview':
        return isDark ? tealDark : tealLight;
      default:
        return isDark ? accentDark : racingGreen;
    }
  }
}

class AppSpacing {
  // Strict 4-pt Spacing System with half-step micro-paddings
  static const double s2 = 2.0;
  static const double s4 = 4.0;
  static const double s6 = 6.0;
  static const double s8 = 8.0;
  static const double s10 = 10.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;
  static const double s28 = 28.0;
  static const double s32 = 32.0;
  static const double s40 = 40.0;
  static const double s48 = 48.0;
}

class AppRadii {
  static const double card = 16.0;
  static const double control = 10.0;
  static const double badge = 6.0;
  static const double pill = 999.0;
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
        secondary: AppColors.brassLight,
        error: AppColors.errorLight,
      ),
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvasLight,
        foregroundColor: AppColors.textPrimaryLight,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.6,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.4,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.2,
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
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondaryLight,
          height: 1.35,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
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
          side: const BorderSide(color: AppColors.borderHairlineLight, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        indicatorColor: AppColors.racingGreenSubtle,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.accentLight);
          }
          return const IconThemeData(color: AppColors.textMutedLight);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accentLight,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textMutedLight,
          );
        }),
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
        secondary: AppColors.brassDark,
        error: AppColors.errorDark,
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
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryDark,
          letterSpacing: -0.6,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimaryDark,
          letterSpacing: -0.4,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
          letterSpacing: -0.2,
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
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondaryDark,
          height: 1.35,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
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
          side: const BorderSide(color: AppColors.borderHairlineDark, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        indicatorColor: AppColors.surfaceSubtleDark,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.accentDark);
          }
          return const IconThemeData(color: AppColors.textMutedDark);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accentDark,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textMutedDark,
          );
        }),
      ),
    );
  }
}
