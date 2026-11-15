import 'dart:ui';
import 'package:flutter/material.dart';

/// ApplyPilot Apple Music-Inspired Design System
/// Combines Apple Music's dark editorial refinement with Hallmark craft:
/// - Rich near-black backgrounds (#0A0A0C to #101014)
/// - Deep charcoal surfaces (#141418, #1C1C24)
/// - Strong white typography with hierarchy (#F5F5F7, #8E8E93, #636366)
/// - Restrained semantic accents: Emerald, Coral, Violet, Blue, Amber
/// - Translucent surfaces with BackdropFilter blur
/// - Compact controls, table-style list rows, no repetitive cards-in-cards
class AppleMusicTheme {
  // 1. Dark Surfaces & Foundations
  static const Color background = Color(0xFF0E0F0E);
  static const Color surface = Color(0xFF161816);
  static const Color surfaceElevated = Color(0xFF1C201D);
  static const Color surfaceSubtle = Color(0xFF121412);
  static const Color frostedGlass = Color(0xCC161816);
  static const Color hairline = Color(0xFF262926);
  static const Color hairlineProminent = Color(0xFF353935);

  // 2. High-Fidelity Typography
  static const Color textPrimary = Color(0xFFECEEEC);
  static const Color textSecondary = Color(0xFFA0A69F);
  static const Color textTertiary = Color(0xFF6E736E);

  // 3. Restrained Semantic Color System
  static const Color emerald = Color(0xFF7FD1A8); // Signature Accent & Successful operations
  static const Color emeraldSubtle = Color(0x1F7FD1A8);

  static const Color coral = Color(0xFFF87171); // Critical errors, pause, rejection
  static const Color coralSubtle = Color(0x1FF87171);

  static const Color violet = Color(0xFFA78BFA); // Gemini AI intelligence, copilot
  static const Color violetSubtle = Color(0x1FA78BFA);

  static const Color blue = Color(0xFF60A5FA); // Discovery, links, telemetry
  static const Color blueSubtle = Color(0x1F60A5FA);

  static const Color amber = Color(0xFFFBBF24); // Pending approval, waiting, warnings
  static const Color amberSubtle = Color(0x1FFBBF24);

  // 4. Geometry & Radii
  static const double radiusControl = 8.0;
  static const double radiusCard = 12.0;
  static const double radiusPill = 999.0;

  // 5. Typography Scale
  static const TextStyle displayLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    color: textPrimary,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: textPrimary,
  );

  static const TextStyle itemTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textTertiary,
  );

  static const TextStyle metricLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // 6. Common Apple Music UI Containers
  static Widget sectionTitle(String title, {String? subtitle, Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sectionHeader),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: caption),
                ],
              ],
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  static BoxDecoration cardDecoration({bool isSelected = false, Color? customBg}) {
    return BoxDecoration(
      color: customBg ?? surface,
      borderRadius: BorderRadius.circular(radiusCard),
      border: Border.all(
        color: isSelected ? hairlineProminent : hairline,
        width: 1.0,
      ),
    );
  }

  static Widget frostedContainer({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    double borderRadius = radiusCard,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: frostedGlass,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: hairline, width: 1.0),
          ),
          child: child,
        ),
      ),
    );
  }

  /// 4-Level Evidence Badge:
  /// Level 1: Simulation (Dry-Run)
  /// Level 2: Form Completed — Not Submitted
  /// Level 3: Submission Attempted — Confirmation Pending
  /// Level 4: Application Confirmed
  static Widget evidenceBadge(int level, {String? customText}) {
    Color bg;
    Color border;
    Color fg;
    String label;
    IconData icon;

    switch (level) {
      case 4:
        bg = emeraldSubtle;
        border = emerald.withOpacity(0.4);
        fg = emerald;
        label = customText ?? "Confirmed Submitted";
        icon = Icons.check_circle_outlined;
        break;
      case 3:
        bg = blueSubtle;
        border = blue.withOpacity(0.4);
        fg = blue;
        label = customText ?? "Submission Attempted";
        icon = Icons.send_outlined;
        break;
      case 2:
        bg = amberSubtle;
        border = amber.withOpacity(0.4);
        fg = amber;
        label = customText ?? "Form Completed (Unsubmitted)";
        icon = Icons.assignment_turned_in_outlined;
        break;
      case 1:
      default:
        bg = surfaceElevated;
        border = hairlineProminent;
        fg = textSecondary;
        label = customText ?? "Dry-Run Simulation";
        icon = Icons.science_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radiusControl),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
