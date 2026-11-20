import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'shell_config.dart';
import 'shell_theme.dart';

/// First run: two short welcome pages, then sign-in. "Change server" opens straight on sign-in.
/// Styled from the same tokens as the cockpit so the app feels like one piece from the first tap.
class ConnectScreen extends StatefulWidget {
  final ShellConfig initial;
  final String? message;
  final ValueChanged<ShellConfig> onConnected;
  final VoidCallback? onCancel;
  final ShellPalette palette;
  final bool showIntro;

  const ConnectScreen({
    super.key,
    required this.initial,
    required this.onConnected,
    this.message,
    this.onCancel,
    this.palette = ShellPalette.neutral,
    this.showIntro = false,
  });

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final PageController _pages = PageController();
  late final TextEditingController _url = TextEditingController(text: widget.initial.serverUrl);
  late final TextEditingController _token = TextEditingController(text: widget.initial.token);
  final _urlFocus = FocusNode();
  final _tokenFocus = FocusNode();
  late bool _intro = widget.showIntro && widget.message == null;
  int _page = 0;
  bool _busy = false;
  bool _done = false;
  bool _showToken = false;
  late bool _editServer = widget.initial.serverUrl.isEmpty;
  String? _error;

  ShellUi get ui => ShellUi(widget.palette);

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    _token.addListener(() => setState(() {}));
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pages.dispose();
    _url.dispose();
    _token.dispose();
    _urlFocus.dispose();
    _tokenFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && !_done && _token.text.trim().isNotEmpty && _url.text.trim().isNotEmpty;

  String get _host {
    final u = Uri.tryParse(ShellConfig.normalizeUrl(_url.text));
    return (u == null || u.host.isEmpty) ? _url.text.trim() : u.host + (u.hasPort && u.port != 443 && u.port != 80 ? ':${u.port}' : '');
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_page < 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    } else {
      _startSignIn();
    }
  }

  void _startSignIn() {
    setState(() => _intro = false);
    Future.delayed(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      (_editServer ? _urlFocus : _tokenFocus).requestFocus();
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) return;
    // A sign-in link (https://server/app/?token=…) fills in both fields at once.
    final link = Uri.tryParse(text);
    if (link != null && link.hasScheme && link.queryParameters['token'] != null) {
      _url.text = '${link.scheme}://${link.host}${link.hasPort ? ':${link.port}' : ''}';
      _token.text = link.queryParameters['token']!;
      setState(() => _editServer = false);
    } else {
      _token.text = text;
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _signIn() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    final err = await ShellConfig.test(_url.text, _token.text);
    if (!mounted) return;
    if (err != null) {
      HapticFeedback.heavyImpact();
      setState(() { _busy = false; _error = err; if (err.contains('reach')) _editServer = true; });
      return;
    }
    final cfg = await ShellConfig.save(_url.text, _token.text);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() { _busy = false; _done = true; });
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) widget.onConnected(cfg);
  }

  void _help() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ui.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your access key', style: TextStyle(color: ui.ink, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            const SizedBox(height: 8),
            Text('It\'s the key that unlocks your ApplyPilot server, so only you can use it.',
                style: TextStyle(color: ui.ink2, fontSize: 14, height: 1.45)),
            const SizedBox(height: 18),
            _helpStep('1', 'On the computer where ApplyPilot is set up, open the web app.'),
            _helpStep('2', 'Go to Settings › Data & privacy and copy your access key.'),
            _helpStep('3', 'Paste it here. The app remembers it, so you only do this once.'),
            const SizedBox(height: 6),
            Text('Tip: copy the whole sign-in link and tap Paste. The server and key fill in together.',
                style: TextStyle(color: ui.ink3, fontSize: 13, height: 1.4)),
          ]),
        ),
      ),
    );
  }

  Widget _helpStep(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24, height: 24, alignment: Alignment.center,
            decoration: BoxDecoration(color: ui.soft, shape: BoxShape.circle),
            child: Text(n, style: TextStyle(color: ui.ink, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: ui.ink, fontSize: 14.5, height: 1.4))),
        ]),
      );

  // ───────────────────────── Shared pieces ─────────────────────────
  Widget _primary(String label, VoidCallback? onTap, {Widget? child}) => SizedBox(
        height: 56,
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _done ? ShellUi.teal : ui.button,
            foregroundColor: ui.buttonInk,
            disabledBackgroundColor: _done ? ShellUi.teal : ui.button.withValues(alpha: 0.28),
            disabledForegroundColor: _done ? Colors.white : ui.buttonInk.withValues(alpha: 0.8),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, letterSpacing: -0.1),
          ),
          onPressed: onTap,
          child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: child ?? Text(label, key: ValueKey(label))),
        ),
      );

  Widget _dots(int active) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == active ? 22 : 6,
              height: 6,
              decoration: BoxDecoration(color: i == active ? ui.ink : ui.ink3.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(3)),
            )),
      );

  Widget _feature(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: ui.card, borderRadius: BorderRadius.circular(14), boxShadow: ui.cardShadow, border: Border.all(color: ui.hair)),
            child: Icon(icon, color: ui.ink, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: ui.ink, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: ui.ink2, fontSize: 13.5, height: 1.35)),
          ])),
        ]),
      );

  // ───────────────────────── Welcome pages ─────────────────────────
  Widget _introPage({required Widget hero, required String title, required String body, required List<Widget> features}) =>
      LayoutBuilder(builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                hero,
                const SizedBox(height: 28),
                Text(title, style: TextStyle(color: ui.ink, fontSize: 32, height: 1.12, fontWeight: FontWeight.w700, letterSpacing: -0.9)),
                const SizedBox(height: 12),
                Text(body, style: TextStyle(color: ui.ink2, fontSize: 16, height: 1.45)),
                const SizedBox(height: 32),
                ...features,
              ]),
            ),
          ));

  Widget _iconHero(IconData icon) => Container(
        width: 64, height: 64,
        decoration: BoxDecoration(color: ui.card, borderRadius: BorderRadius.circular(20), boxShadow: ui.cardShadow, border: Border.all(color: ui.hair)),
        child: Icon(icon, color: ui.ink, size: 30),
      );

  Widget _introView() => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [
            const SizedBox(width: 12),
            Text('ApplyPilot', style: TextStyle(color: ui.ink, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
            const Spacer(),
            TextButton(onPressed: _startSignIn, child: Text('Sign in', style: TextStyle(color: ui.ink2, fontSize: 15, fontWeight: FontWeight.w600))),
          ]),
        ),
        Expanded(
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              _introPage(
                hero: BrandMark(size: 72, dark: ui.dark),
                title: 'Your job search,\non autopilot',
                body: 'ApplyPilot finds roles that fit you, fills in the applications and keeps proof of every one, while you get on with your day.',
                features: [
                  _feature(Icons.travel_explore_rounded, 'Finds roles that fit', 'Scored against your skills and preferences'),
                  _feature(Icons.edit_note_rounded, 'Fills every form', 'From your profile, your answers and AI'),
                  _feature(Icons.verified_outlined, 'Keeps the receipts', 'Employer emails become proof'),
                ],
              ),
              _introPage(
                hero: _iconHero(Icons.shield_outlined),
                title: 'You stay\nin control',
                body: 'Nothing goes out behind your back. You decide when it starts sending, and it checks with you when it isn\'t sure.',
                features: [
                  _feature(Icons.science_outlined, 'Practice runs first', 'Nothing is sent until you turn on live mode'),
                  _feature(Icons.notifications_none_rounded, 'Asks when unsure', 'Questions only you can answer go to Needs You'),
                  _feature(Icons.lock_outline_rounded, 'Private by design', 'Your data stays on your own server'),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(children: [
            _dots(_page),
            const SizedBox(height: 20),
            _primary(_page == 0 ? 'Get started' : 'Continue', _next),
          ]),
        ),
      ]);

  // ───────────────────────── Sign in ─────────────────────────
  Widget _signInView() {
    final firstRun = widget.showIntro;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
        child: Row(children: [
          if (firstRun && widget.onCancel == null)
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: ui.ink),
              tooltip: 'Back',
              onPressed: () { setState(() { _intro = true; _page = 0; }); },
            )
          else
            const SizedBox(width: 48),
          const Spacer(),
          if (widget.onCancel != null)
            TextButton(onPressed: widget.onCancel, child: Text('Cancel', style: TextStyle(color: ui.ink2, fontSize: 15, fontWeight: FontWeight.w600))),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BrandMark(size: 52, dark: ui.dark),
            const SizedBox(height: 24),
            Text(widget.onCancel != null ? 'Switch server' : 'Sign in', style: TextStyle(color: ui.ink, fontSize: 32, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.9)),
            const SizedBox(height: 10),
            Text('Enter your server and access key. The app remembers them, so you only do this once.',
                style: TextStyle(color: ui.ink2, fontSize: 15.5, height: 1.45)),
            const SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(color: ui.card, borderRadius: BorderRadius.circular(22), boxShadow: ui.cardShadow, border: Border.all(color: ui.hair)),
              child: Column(children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: _editServer || _url.text.trim().isEmpty ? _serverField() : _serverRow(),
                ),
                Divider(height: 1, thickness: 1, color: ui.hair, indent: 16, endIndent: 16),
                _tokenField(),
              ]),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: _error == null ? const SizedBox(width: double.infinity) : Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: ShellUi.coral.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline_rounded, color: ShellUi.coral, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: TextStyle(color: ui.ink, fontSize: 14, height: 1.4))),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _primary(
              'Sign in',
              _canSubmit ? _signIn : null,
              child: _busy
                  ? SizedBox(key: const ValueKey('busy'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: ui.buttonInk))
                  : _done
                      ? const Row(key: ValueKey('done'), mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_rounded, color: Colors.white), SizedBox(width: 8),
                          Text('Signed in', style: TextStyle(color: Colors.white)),
                        ])
                      : Text(widget.onCancel != null ? 'Connect' : 'Sign in', key: const ValueKey('idle')),
            ),
            const SizedBox(height: 8),
            Center(child: TextButton(
              onPressed: _help,
              child: Text('Where do I find my access key?', style: TextStyle(color: ui.ink2, fontSize: 14.5, fontWeight: FontWeight.w600)),
            )),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: ui.ink3),
              const SizedBox(width: 6),
              Text('Secured with HTTPS · your key stays on this phone', style: TextStyle(color: ui.ink3, fontSize: 12.5)),
            ]),
            if (firstRun && widget.onCancel == null) ...[
              const SizedBox(height: 18),
              _dots(2),
            ],
          ]),
        ),
      ),
    ]);
  }

  InputDecoration _input(String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: ui.ink3, fontSize: 15),
        floatingLabelStyle: TextStyle(color: ui.ink2, fontSize: 14, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: ui.ink3.withValues(alpha: 0.7)),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        suffixIcon: suffix,
      );

  Widget _serverRow() => InkWell(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        onTap: () { setState(() => _editServer = true); Future.microtask(() => _urlFocus.requestFocus()); },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(children: [
            Icon(Icons.dns_outlined, size: 20, color: ui.ink2),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Server', style: TextStyle(color: ui.ink3, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ui.ink, fontSize: 15.5)),
            ])),
            Text('Change', style: TextStyle(color: ui.ink2, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
          ]),
        ),
      );

  Widget _serverField() => TextField(
        controller: _url,
        focusNode: _urlFocus,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.url],
        style: TextStyle(color: ui.ink, fontSize: 16),
        cursorColor: ui.ink,
        decoration: _input('Server address', hint: 'https://your-server.sslip.io'),
        onSubmitted: (_) => _tokenFocus.requestFocus(),
      );

  Widget _tokenField() => TextField(
        controller: _token,
        focusNode: _tokenFocus,
        obscureText: !_showToken,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        style: TextStyle(color: ui.ink, fontSize: 16, letterSpacing: _showToken ? 0 : 1.5),
        cursorColor: ui.ink,
        decoration: _input('Access key', suffix: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_token.text.isEmpty)
            TextButton(onPressed: _paste, child: Text('Paste', style: TextStyle(color: ui.ink, fontWeight: FontWeight.w600)))
          else
            IconButton(
              tooltip: _showToken ? 'Hide key' : 'Show key',
              icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: ui.ink2, size: 21),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
          const SizedBox(width: 4),
        ])),
        onSubmitted: (_) => _signIn(),
      );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: widget.palette.overlay,
      child: Scaffold(
        backgroundColor: ui.bg,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim), child: child),
            ),
            child: _intro ? KeyedSubtree(key: const ValueKey('intro'), child: _introView()) : KeyedSubtree(key: const ValueKey('signin'), child: _signInView()),
          ),
        ),
      ),
    );
  }
}
