import 'package:flutter/material.dart';

/// Ultra-premium Dark Theme Design Tokens for ApplyPilot
/// Combining Shadcn modern minimalism with Kite SaaS dashboard tokens.
class TemplateTokens {
  // 1. Core Surfaces & Backgrounds (Google Stitch Neutral Monochrome)
  static const Color background = Color(0xFF0F0F10);
  static const Color surface = Color(0xFF18181A);
  static const Color surfaceElevated = Color(0xFF242426);
  static const Color surfaceSubtle = Color(0xFF0E0E0E);
  static const Color border = Color(0xFF2C2C2E);
  static const Color borderHover = Color(0xFF38383A);

  // 2. High-Contrast Typography
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textMuted = Color(0xFF636366);

  // 3. Signature Accents & Semantic Tones (Stitch Palette)
  static const Color accent = Color(0xFFF59E0B); // Stitch Warm Amber / Gold
  static const Color accentSubtle = Color(0x1FF59E0B);
  static const Color success = Color(0xFF30D158); // Apple Success Green
  static const Color successSubtle = Color(0x1F30D158);
  static const Color racingGreen = Color(0xFF1B4332);
  static const Color brass = Color(0xFFD4AF37); // Muted gold / brass
  static const Color brassSubtle = Color(0x1FD4AF37);
  static const Color error = Color(0xFFFF453A); // Stitch iOS Red
  static const Color errorSubtle = Color(0x1FFF453A);
  static const Color warning = Color(0xFFF59E0B); // Warm Amber
  static const Color warningSubtle = Color(0x1FF59E0B);
  static const Color info = Color(0xFF0A84FF); // iOS Blue
  static const Color infoSubtle = Color(0x1F0A84FF);
  static const Color aiViolet = Color(0xFFBF5AF2); // Stitch Review Violet

  // Google Stitch Executive Design Tokens
  static const Color stitchBackground = Color(0xFF0F0F10);
  static const Color stitchSurfaceCard = Color(0xFF18181A);
  static const Color stitchSurfaceElevated = Color(0xFF242426);
  static const Color stitchSurfaceLowest = Color(0xFF0E0E0E);
  static const Color stitchHairline = Color(0xFF2C2C2E);
  static const Color stitchCyan = Color(0xFF64E4FD);
  static const Color stitchJade = Color(0xFF30D158);
  static const Color stitchAmber = Color(0xFFF59E0B);
  static const Color stitchTerracotta = Color(0xFFEA580C);
  static const Color stitchError = Color(0xFFFF453A);
  static const Color stitchZincSubtle = Color(0xFF8E8E93);
  static const Color stitchZincSubtle = Color(0xFF8E8E93);

  // 4. Spacing Scale (4pt Grid System)
  static const double s2 = 2.0;
  static const double s4 = 4.0;
  static const double s6 = 6.0;
  static const double s8 = 8.0;
  static const double s10 = 10.0;
  static const double s12 = 12.0;
  static const double s14 = 14.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double s40 = 40.0;
  static const double s48 = 48.0;

  // 5. Border Radii (Shadcn-inspired)
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 14.0;
  static const double radiusXl = 20.0;
  static const double radiusPill = 999.0;

  // 6. Responsive Layout Breakpoints
  static const double breakpointMobile = 650.0;
  static const double breakpointTablet = 950.0;
  static const double breakpointDesktop = 1200.0;

  static bool isMobile(BuildContext context) => MediaQuery.of(context).size.width < breakpointMobile;
  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= breakpointMobile && w < breakpointTablet;
  }
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= breakpointTablet;
}
