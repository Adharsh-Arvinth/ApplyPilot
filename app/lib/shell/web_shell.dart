import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'shell_config.dart';
import 'shell_theme.dart';

/// Full-screen host for the ApplyPilot web cockpit served by the PC backend.
class WebShell extends StatefulWidget {
  final ShellConfig config;
  final void Function(String? reason) onChangeServer;

  const WebShell({super.key, required this.config, required this.onChangeServer});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late final WebViewController _web;
  bool _loading = true;
  String? _error;
  ShellPalette _palette = ShellPalette.neutral;

  Uri get _base => Uri.parse(widget.config.serverUrl);

  bool _sameServer(Uri u) => u.host == _base.host && u.port == _base.port && u.scheme == _base.scheme;

  @override
  void initState() {
    super.initState();
    // Start in the last theme the cockpit reported, so there is no colour flash on launch.
    ShellPalette.load().then((p) { if (mounted) _setPalette(p, persist: false); });
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_palette.bg)
      ..addJavaScriptChannel('ApplyPilotShell', onMessageReceived: (m) {
        if (m.message == 'change-server') { widget.onChangeServer(null); return; }
        final p = ShellPalette.fromMessage(m.message);
        if (p != null) _setPalette(p);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() => _loading = true); },
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); },
        onWebResourceError: (e) {
          if (e.isForMainFrame == false) return;
          if (mounted) setState(() { _error = e.description; _loading = false; });
        },
        onHttpError: (e) {
          final uri = e.request?.uri;
          final code = e.response?.statusCode ?? 0;
          if (uri != null && _sameServer(uri) && uri.path.startsWith('/app') && (code == 401 || code == 403)) {
            widget.onChangeServer('The server rejected the saved token. Enter the current one from backend/.env.');
          }
        },
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          if (_sameServer(uri) && !uri.path.startsWith('/output/')) return NavigationDecision.navigate;
          _openExternally(uri);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(widget.config.cockpitUri());
  }

  /// Job postings open in the phone's browser. Resumes and screenshots (/output/) need
  /// the token because the browser doesn't share the app's session cookie.
  Future<void> _openExternally(Uri uri) async {
    var target = uri;
    if (_sameServer(uri)) {
      target = uri.replace(queryParameters: {...uri.queryParameters, 'token': widget.config.token});
    }
    if (!await launchUrl(target, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t open ${uri.host}')));
    }
  }

  /// Repaint the native chrome (status/navigation bars, background) to match the cockpit theme.
  void _setPalette(ShellPalette p, {bool persist = true}) {
    if (p == _palette) return;
    setState(() => _palette = p);
    _web.setBackgroundColor(p.bg);
    if (persist) p.save();
  }

  void _retry() {
    setState(() { _error = null; _loading = true; });
    _web.loadRequest(widget.config.cockpitUri());
  }

  /// Android back: let the cockpit close its sheet/palette or return to Today first.
  Future<void> _onBack() async {
    if (_error == null) {
      try {
        final handled = await _web.runJavaScriptReturningResult('window.__apBack ? window.__apBack() : false');
        if (handled == true || handled.toString() == 'true') return;
      } catch (_) {}
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _onBack(); },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _palette.overlay,
        child: Scaffold(
          backgroundColor: _palette.bg,
          // Keep the cockpit clear of the status bar and gesture/nav bar (Android 15 is edge-to-edge).
          body: SafeArea(
            child: Stack(children: [
              if (_error == null) WebViewWidget(controller: _web),
              if (_error != null) _errorView(),
              if (_loading && _error == null)
                Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2, color: _palette.ink, backgroundColor: Colors.transparent)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, color: _palette.ink2, size: 40),
            const SizedBox(height: 16),
            Text('Can\'t reach your PC', style: TextStyle(color: _palette.ink, fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Make sure the ApplyPilot backend is running at ${widget.config.serverUrl} and Tailscale is on.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _palette.ink2, fontSize: 14, height: 1.4),
            ),
            if (_error!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: _palette.ink3, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _palette.ink, foregroundColor: _palette.bg, minimumSize: const Size(200, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: _retry,
              child: const Text('Try again'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => widget.onChangeServer(null), child: Text('Change server', style: TextStyle(color: _palette.ink2))),
          ]),
        ),
      );
}
