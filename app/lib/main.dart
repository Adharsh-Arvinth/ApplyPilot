import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'shell/connect_screen.dart';
import 'shell/shell_config.dart';
import 'shell/shell_theme.dart';
import 'shell/web_shell.dart';

/// ApplyPilot for Android: a native shell around the command-center cockpit
/// served by the backend on your PC (backend/app/static/cockpit).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await ShellConfig.load();
  final palette = await ShellPalette.load(); // the theme picked in the app last time (Neutral on a new install)
  SystemChrome.setSystemUIOverlayStyle(palette.overlay);
  runApp(ApplyPilotApp(initialConfig: config, palette: palette));
}

class ApplyPilotApp extends StatefulWidget {
  final ShellConfig initialConfig;
  final ShellPalette palette;

  const ApplyPilotApp({super.key, required this.initialConfig, this.palette = ShellPalette.neutral});

  @override
  State<ApplyPilotApp> createState() => _ApplyPilotAppState();
}

class _ApplyPilotAppState extends State<ApplyPilotApp> {
  late ShellConfig _config = widget.initialConfig;
  late bool _connecting = !widget.initialConfig.ready;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (_connecting) {
      home = ConnectScreen(
        key: ValueKey('connect-${_config.serverUrl}-$_message'),
        initial: _config,
        message: _message,
        palette: widget.palette,
        showIntro: !_config.ready,
        onCancel: _config.ready ? () => setState(() { _connecting = false; _message = null; }) : null,
        onConnected: (cfg) => setState(() { _config = cfg; _connecting = false; _message = null; }),
      );
    } else {
      home = WebShell(
        key: ValueKey('shell-${_config.serverUrl}-${_config.token.hashCode}'),
        config: _config,
        onChangeServer: (reason) => setState(() { _connecting = true; _message = reason; }),
      );
    }
    return MaterialApp(
      title: 'ApplyPilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: widget.palette.dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: widget.palette.bg,
        colorScheme: widget.palette.dark
            ? ColorScheme.dark(primary: widget.palette.ink, surface: const Color(0xFF1C1C1E))
            : ColorScheme.light(primary: widget.palette.ink, surface: Colors.white),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: widget.palette.ink,
          selectionColor: widget.palette.ink.withValues(alpha: 0.18),
          selectionHandleColor: widget.palette.ink,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()}),
        useMaterial3: true,
      ),
      home: home,
    );
  }
}
