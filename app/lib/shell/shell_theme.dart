import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stitch "Neutral Monochrome" tokens, used by the connect screen.
class ShellColors {
  static const bg = Color(0xFF000000);
  static const card = Color(0xFF141416);
  static const line = Color(0xFF2A2A2C);
  static const ink = Color(0xFFF2F1EE);
  static const ink2 = Color(0xFF9A9892);
  static const ink3 = Color(0xFF6B6A65);
  static const coral = Color(0xFFE0674F);
}

/// Colours of the native chrome around the web cockpit (status bar, navigation bar,
/// loading/error screens). The cockpit sends its theme as "theme:#RRGGBB:light|dark";
/// the last one is remembered so the next launch starts in the right colours.
class ShellPalette {
  final Color bg;
  final bool dark;

  const ShellPalette(this.bg, this.dark);

  /// Neutral (the cockpit's default theme) until the page reports otherwise.
  static const neutral = ShellPalette(Color(0xFFF4F4F2), false);

  Color get ink => dark ? const Color(0xFFF2F2F3) : const Color(0xFF1C1C1E);
  Color get ink2 => dark ? const Color(0xFFA5A5AA) : const Color(0xFF57575C);
  Color get ink3 => dark ? const Color(0xFF909096) : const Color(0xFF6C6C71);

  SystemUiOverlayStyle get overlay => SystemUiOverlayStyle(
        statusBarColor: bg,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      );

  /// Parses "theme:#RRGGBB:light|dark"; returns null for anything else.
  static ShellPalette? fromMessage(String message) {
    final parts = message.split(':');
    if (parts.length != 3 || parts[0] != 'theme') return null;
    final hex = parts[1].trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return ShellPalette(Color(0xFF000000 | int.parse(hex, radix: 16)), parts[2].trim() == 'dark');
  }

  static Future<ShellPalette> load() async {
    final prefs = await SharedPreferences.getInstance();
    final bg = prefs.getInt('shell_bg');
    return bg == null ? neutral : ShellPalette(Color(bg), prefs.getBool('shell_dark') ?? false);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shell_bg', bg.toARGB32());
    await prefs.setBool('shell_dark', dark);
  }

  @override
  bool operator ==(Object other) => other is ShellPalette && other.bg == bg && other.dark == dark;

  @override
  int get hashCode => Object.hash(bg, dark);
}

/// Colours for the native first-run screens, derived from the cockpit theme the
/// user last picked (Neutral light on a fresh install), so the app looks like one piece.
class ShellUi {
  final ShellPalette p;
  const ShellUi(this.p);

  bool get dark => p.dark;
  Color get bg => p.bg;
  Color get ink => p.ink;
  Color get ink2 => p.ink2;
  Color get ink3 => p.ink3;
  Color get card => dark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get field => dark ? const Color(0xFF232326) : const Color(0xFFF7F7F5);
  Color get hair => dark ? const Color(0x1FFFFFFF) : const Color(0x12000000);
  Color get button => dark ? const Color(0xFFF2F2F3) : const Color(0xFF1C1C1E);
  Color get buttonInk => dark ? const Color(0xFF111113) : Colors.white;
  Color get soft => dark ? const Color(0x14FFFFFF) : const Color(0x0B1C1C1E);
  static const teal = Color(0xFF34B394);
  static const coral = Color(0xFFDD6E5E);

  List<BoxShadow> get cardShadow => dark
      ? const []
      : const [BoxShadow(color: Color(0x0F000000), blurRadius: 24, offset: Offset(0, 8)), BoxShadow(color: Color(0x08000000), blurRadius: 2)];
}

/// The ApplyPilot mark (same gradient square as the cockpit's brand mark).
class BrandMark extends StatelessWidget {
  final double size;
  final bool dark;
  const BrandMark({super.key, this.size = 64, this.dark = false});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark ? const [Color(0xFF8E8E93), Color(0xFF3A3A3C)] : const [Color(0xFF6E6E73), Color(0xFF1C1C1E)],
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: size * 0.4, offset: Offset(0, size * 0.14), spreadRadius: -size * 0.12)],
        ),
        child: Text('AP', style: TextStyle(color: Colors.white, fontSize: size * 0.34, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
      );
}
