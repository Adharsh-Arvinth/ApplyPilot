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
