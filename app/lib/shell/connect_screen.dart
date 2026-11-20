import 'package:flutter/material.dart';
import 'shell_config.dart';
import 'shell_theme.dart';

/// First-run (and "change server") screen: where is the PC, and what's the token.
class ConnectScreen extends StatefulWidget {
  final ShellConfig initial;
  final String? message;
  final ValueChanged<ShellConfig> onConnected;
  final VoidCallback? onCancel;

  const ConnectScreen({super.key, required this.initial, required this.onConnected, this.message, this.onCancel});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _url = TextEditingController(text: widget.initial.serverUrl);
  late final TextEditingController _token = TextEditingController(text: widget.initial.token);
  bool _busy = false;
  bool _showToken = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    final err = await ShellConfig.test(_url.text, _token.text);
    if (!mounted) return;
    if (err != null) {
      setState(() { _busy = false; _error = err; });
      return;
    }
    final cfg = await ShellConfig.save(_url.text, _token.text);
    if (!mounted) return;
    widget.onConnected(cfg);
  }

  InputDecoration _field(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: ShellColors.ink2),
        filled: true,
        fillColor: ShellColors.card,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ShellColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ShellColors.ink)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: ShellColors.ink, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: const Text('AP', style: TextStyle(color: ShellColors.bg, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              if (widget.onCancel != null)
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel', style: TextStyle(color: ShellColors.ink2))),
            ]),
            const SizedBox(height: 28),
            const Text('Connect to\nyour server', style: TextStyle(color: ShellColors.ink, fontSize: 32, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -0.8)),
            const SizedBox(height: 10),
            const Text(
              'Enter your ApplyPilot server address and your token. You only do this once.',
              style: TextStyle(color: ShellColors.ink2, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: const TextStyle(color: ShellColors.ink),
              decoration: _field('Server address'),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('e.g. https://your-server.sslip.io', style: TextStyle(color: ShellColors.ink3, fontSize: 12)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              obscureText: !_showToken,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(color: ShellColors.ink),
              decoration: _field('Token', suffix: IconButton(
                icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: ShellColors.ink2),
                onPressed: () => setState(() => _showToken = !_showToken),
              )),
              onSubmitted: (_) => _connect(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ShellColors.coral.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ShellColors.coral.withValues(alpha: 0.35)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline, color: ShellColors.coral, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(color: ShellColors.ink, fontSize: 14, height: 1.35))),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ShellColors.ink,
                  foregroundColor: ShellColors.bg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                onPressed: _busy ? null : _connect,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: ShellColors.bg))
                    : const Text('Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
