import 'package:flutter/material.dart';

/// Ultra-premium Dark Theme Design Tokens for ApplyPilot
/// Combining Shadcn modern minimalism with Kite SaaS dashboard tokens.
class TemplateTokens {
  // 1. Core Surfaces & Backgrounds
  static const Color background = Color(0xFF0E0F0E);
  static const Color surface = Color(0xFF161816);
  static const Color surfaceElevated = Color(0xFF1E211E);
  static const Color surfaceSubtle = Color(0xFF121412);
  static const Color border = Color(0xFF262926);
  static const Color borderHover = Color(0xFF383D38);

  // 2. High-Contrast Typography
  static const Color textPrimary = Color(0xFFECEEEC);
  static const Color textSecondary = Color(0xFFA0A69F);
  static const Color textMuted = Color(0xFF6B726A);

  // 3. Signature Accents & Semantic Tones
  static const Color accent = Color(0xFF7FD1A8); // Jade / Mint Green
  static const Color accentSubtle = Color(0x1F7FD1A8);
  static const Color success = Color(0xFF7FD1A8);
  static const Color successSubtle = Color(0x1F7FD1A8);
  static const Color racingGreen = Color(0xFF1B4332);
  static const Color brass = Color(0xFFD4AF37); // Muted gold / brass
  static const Color brassSubtle = Color(0x1FD4AF37);
  static const Color error = Color(0xFFF87171); // Soft Coral
  static const Color errorSubtle = Color(0x1FF87171);
  static const Color warning = Color(0xFFFBBF24); // Warm Amber
  static const Color warningSubtle = Color(0x1FFBBF24);
  static const Color info = Color(0xFF38BDF8); // Sky Blue
  static const Color infoSubtle = Color(0x1F38BDF8);
  static const Color aiViolet = Color(0xFFA78BFA); // Gemini AI Violet

  // Google Stitch Executive Design Tokens (Asset: f7e9b289f0ab4257a02dc33ecd3181d8)
  static const Color stitchBackground = Color(0xFF131313);
  static const Color stitchSurfaceCard = Color(0xFF1C1C1E);
  static const Color stitchSurfaceElevated = Color(0xFF2C2C2E);
  static const Color stitchSurfaceLowest = Color(0xFF0E0E0E);
  static const Color stitchHairline = Color(0xFF38383A);
  static const Color stitchCyan = Color(0xFF64E4FD);
  static const Color stitchJade = Color(0xFF7FD1A8);
  static const Color stitchAmber = Color(0xFFF59E0B);
  static const Color stitchTerracotta = Color(0xFFEA580C);
  static const Color stitchError = Color(0xFFFF453A);
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
