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
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: ShellColors.bg,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: ShellColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final config = await ShellConfig.load();
  runApp(ApplyPilotApp(initialConfig: config));
}

class ApplyPilotApp extends StatefulWidget {
  final ShellConfig initialConfig;

  const ApplyPilotApp({super.key, required this.initialConfig});

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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ShellColors.bg,
        colorScheme: const ColorScheme.dark(primary: ShellColors.ink, surface: ShellColors.card),
        useMaterial3: true,
      ),
      home: home,
    );
  }
}
