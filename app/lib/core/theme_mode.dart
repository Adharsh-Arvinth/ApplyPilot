import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode for the legacy native screens (kept for reference; the app now
/// hosts the web cockpit, see lib/shell/).
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

void setThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  themeModeNotifier.value = mode;
  final str = mode == ThemeMode.light ? "light" : (mode == ThemeMode.dark ? "dark" : "system");
  await prefs.setString("theme_mode", str);
}
