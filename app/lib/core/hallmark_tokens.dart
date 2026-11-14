import 'package:flutter/material.dart';

/// Hallmark Design System — Console Theme Tokens
/// "An instrument kept by careful people: a graphite ground stepped in three lightnesses,
/// hairline panels cut from one surface, amber for a person and cool blue for an instrument."
///
/// Designed to eliminate generic AI-generated design slop:
/// - No cards inside cards (Floor 4)
/// - Single containment layer with 1px hairline rules
/// - Amber represents human/operator action (Floor 75)
/// - Cool blue represents automation/instrument telemetry
/// - No tracked-caps labels or eyebrows (Floor 67)
/// - Real measurements with units and timestamps
class HallmarkConsole {
  // 1. Surface Ladder (Three steps of neutral graphite)
  static const Color ground = Color(0xFF0E100E);
  static const Color panel = Color(0xFF151815);
  static const Color well = Color(0xFF111311);
  static const Color panelElevated = Color(0xFF1C201C);

  // 2. Hairlines & Seams
  static const Color rule = Color(0xFF262B26);
  static const Color ruleProminent = Color(0xFF3A423A);

  // 3. Ink & Readability
  static const Color ink = Color(0xFFF2F4F2);
  static const Color inkSecondary = Color(0xFFD4D8D4);
  static const Color muted = Color(0xFF98A098);
  static const Color subtle = Color(0xFF666E66);

  // 4. Hallmark Signals
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberSoft = Color(0x24F59E0B);
  static const Color amberInk = Color(0xFF1A1202);

  static const Color cool = Color(0xFF0284C7);
  static const Color coolLight = Color(0xFF38BDF8);
  static const Color coolSoft = Color(0x240284C7);

  static const Color ok = Color(0xFF10B981);
  static const Color okSoft = Color(0x2410B981);

  static const Color bad = Color(0xFFEF4444);
  static const Color badSoft = Color(0x24EF4444);

  // 5. Geometry & Craft Rules (Hallmark Floor)
  static const double radiusPanel = 10.0;
  static const double radiusControl = 6.0;
  static const double radiusTag = 4.0;
  static const double ruleWidth = 1.0;

  // 6. Common Hallmark Components
  static BoxDecoration panelDecoration({bool isSelected = false, Color? customBg}) {
    return BoxDecoration(
      color: customBg ?? panel,
      borderRadius: BorderRadius.circular(radiusPanel),
      border: Border.all(
        color: isSelected ? ruleProminent : rule,
        width: ruleWidth,
      ),
    );
  }

  static BoxDecoration wellDecoration() {
    return BoxDecoration(
      color: well,
      borderRadius: BorderRadius.circular(radiusPanel),
      border: Border.all(color: rule, width: ruleWidth),
    );
  }

  static BoxDecoration tagDecoration({Color? tint}) {
    final baseColor = tint ?? muted;
    return BoxDecoration(
      color: baseColor.withOpacity(0.12),
      borderRadius: BorderRadius.circular(radiusTag),
      border: Border.all(color: baseColor.withOpacity(0.25), width: ruleWidth),
    );
  }
}
