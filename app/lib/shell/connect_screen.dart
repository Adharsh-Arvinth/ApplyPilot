import 'dart:math' as math;
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
  int _shakes = 0;

  ShellUi get ui => ShellUi(widget.palette);

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    _token.addListener(() => setState(() {}));
    _url.addListener(() => setState(() {}));
    _urlFocus.addListener(() => setState(() {}));
    _tokenFocus.addListener(() => setState(() {}));
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
      setState(() { _busy = false; _error = err; _shakes++; if (err.contains('reach')) _editServer = true; });
      return;
    }
    final cfg = await ShellConfig.save(_url.text, _token.text);
    if (!mounted) return;
    TextInput.finishAutofillContext(); // offers to save the server + key in the phone's password manager
    HapticFeedback.mediumImpact();
    setState(() { _busy = false; _done = true; });
    await Future.delayed(const Duration(milliseconds: 1650));
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
  Widget _primary(String label, VoidCallback? onTap, {Widget? child}) {
    final on = onTap != null || _busy || _done;
    return _PressScale(
      enabled: onTap != null,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: 56,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: on
                ? (ui.dark ? const [Color(0xFFFFFFFF), Color(0xFFE4E4E7)] : const [Color(0xFF3A3A3D), Color(0xFF111113)])
                : [ui.button.withValues(alpha: 0.16), ui.button.withValues(alpha: 0.16)],
          ),
          boxShadow: on
              ? [BoxShadow(color: Colors.black.withValues(alpha: ui.dark ? 0.45 : 0.22), blurRadius: 22, offset: const Offset(0, 10), spreadRadius: -8),
                 BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1))]
              : const [],
        ),
        foregroundDecoration: on ? BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center,
              colors: [Colors.white.withValues(alpha: ui.dark ? 0.0 : 0.10), Colors.white.withValues(alpha: 0.0)]),
        ) : null,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: on ? ui.buttonInk : ui.ink3, fontSize: 16.5, fontWeight: FontWeight.w600, letterSpacing: -0.1),
          child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: child ?? Text(label, key: ValueKey(label))),
        ),
      ),
    );
  }

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
          child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Rise(delay: 0, child: BrandMark(size: 56, dark: ui.dark)),
            const SizedBox(height: 24),
            _Rise(delay: 60, child: Text(widget.onCancel != null ? 'Switch server' : (widget.showIntro ? 'Sign in' : 'Welcome back'), style: TextStyle(color: ui.ink, fontSize: 32, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.9))),
            const SizedBox(height: 10),
            _Rise(delay: 110, child: Text('Sign in with your server and access key. The app remembers them, so you only do this once.',
                style: TextStyle(color: ui.ink2, fontSize: 15.5, height: 1.45))),
            const SizedBox(height: 28),
            _Rise(delay: 170, child: TweenAnimationBuilder<double>(
              key: ValueKey(_shakes),
              tween: Tween(begin: _shakes == 0 ? 1.0 : 0.0, end: 1.0),
              duration: const Duration(milliseconds: 460),
              builder: (_, t, child) => Transform.translate(offset: Offset(math.sin(t * math.pi * 5) * (1 - t) * 9, 0), child: child),
              child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: ui.card, borderRadius: BorderRadius.circular(22),
                border: Border.all(color: (_urlFocus.hasFocus || _tokenFocus.hasFocus) ? ui.ink.withValues(alpha: 0.28) : ui.hair, width: 1),
                boxShadow: [
                  ...ui.cardShadow,
                  if (_urlFocus.hasFocus || _tokenFocus.hasFocus) BoxShadow(color: ui.ink.withValues(alpha: ui.dark ? 0.08 : 0.035), blurRadius: 0, spreadRadius: 3),
                ],
              ),
              child: Column(children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: _editServer || _url.text.trim().isEmpty ? _serverField() : _serverRow(),
                ),
                Divider(height: 1, thickness: 1, color: ui.hair, indent: 16, endIndent: 16),
                _tokenField(),
              ]),
            ))),
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
            _Rise(delay: 230, child: _primary(
              'Sign in',
              _canSubmit ? _signIn : null,
              child: _busy
                  ? SizedBox(key: const ValueKey('busy'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: ui.buttonInk))
                  : _done
                      ? Icon(Icons.check_rounded, key: const ValueKey('done'), color: ui.buttonInk)
                      : Text(widget.onCancel != null ? 'Connect' : 'Sign in', key: const ValueKey('idle')),
            )),
            const SizedBox(height: 8),
            Center(child: TextButton(
              onPressed: _help,
              child: Text('Where do I find my access key?', style: TextStyle(color: ui.ink2, fontSize: 14.5, fontWeight: FontWeight.w600)),
            )),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: ui.ink3),
              const SizedBox(width: 6),
              Flexible(child: Text('Secured with HTTPS · your key stays on this phone', textAlign: TextAlign.center, style: TextStyle(color: ui.ink3, fontSize: 12.5))),
            ]),
            if (firstRun && widget.onCancel == null) ...[
              const SizedBox(height: 18),
              _dots(2),
            ],
          ])),
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
        autofillHints: const [AutofillHints.username, AutofillHints.url],
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
        body: Stack(children: [
          Positioned.fill(child: _Ambient(ui: ui)),
          SafeArea(
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
          if (_done) Positioned.fill(child: _SignedIn(ui: ui, host: _host)),
        ]),
      ),
    );
  }
}

/// Fades and rises into place, a beat after the one before it (staggered entrance).
class _Rise extends StatefulWidget {
  final int delay;
  final Widget child;
  const _Rise({required this.delay, required this.child});
  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () { if (mounted) _c.forward(); });
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(a), child: widget.child));
  }
}

/// Sinks slightly under the finger and springs back, with a light tick: buttons feel physical.
class _PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  const _PressScale({required this.child, this.onTap, this.enabled = true});
  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: widget.enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled ? (_) { setState(() => _down = true); HapticFeedback.selectionClick(); } : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedScale(
            scale: _down ? 0.965 : 1,
            duration: Duration(milliseconds: _down ? 90 : 260),
            curve: _down ? Curves.easeOut : Curves.easeOutBack,
            child: widget.child,
          ),
        ),
      );
}

/// Two soft, slowly drifting glows behind the screen: depth without noise.
class _Ambient extends StatefulWidget {
  final ShellUi ui;
  const _Ambient({required this.ui});
  @override
  State<_Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<_Ambient> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final glow = widget.ui.dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.9);
    final shade = widget.ui.dark ? const Color(0x22000000) : const Color(0x0C1C1C1E);
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = Curves.easeInOut.transform(_c.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment(0.9 - 0.3 * t, -1.0 + 0.2 * t), radius: 1.1, colors: [glow, glow.withValues(alpha: 0)]),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: Alignment(-1.0 + 0.25 * t, 1.0 - 0.15 * t), radius: 1.0, colors: [shade, shade.withValues(alpha: 0)]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The moment you're in: a ring draws itself, a check ticks in, a soft glow blooms, then the app opens.
class _SignedIn extends StatefulWidget {
  final ShellUi ui;
  final String host;
  const _SignedIn({required this.ui, required this.host});
  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 560), () { if (mounted) HapticFeedback.lightImpact(); });
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  Animation<double> _seg(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _c, curve: Interval(a, b, curve: curve));

  @override
  Widget build(BuildContext context) {
    final ui = widget.ui;
    final veil = _seg(0, 0.14), ring = _seg(0.06, 0.42, Curves.easeInOutCubic), check = _seg(0.36, 0.58, Curves.easeOutCubic),
        pop = _seg(0.06, 0.5, Curves.easeOutBack), text = _seg(0.48, 0.78), bloom = _seg(0.36, 0.9, Curves.easeOut);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        color: ui.bg.withValues(alpha: veil.value),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 148, height: 148,
            child: Stack(alignment: Alignment.center, children: [
              Opacity( // a soft bloom that swells and fades behind the ring
                opacity: (1 - bloom.value) * 0.9,
                child: Container(
                  width: 96 + 52 * bloom.value, height: 96 + 52 * bloom.value,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: ShellUi.teal.withValues(alpha: 0.22)),
                ),
              ),
              Transform.scale(
                scale: 0.6 + 0.4 * pop.value,
                child: Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF45C7A6), Color(0xFF239C7E)]),
                    boxShadow: [BoxShadow(color: ShellUi.teal.withValues(alpha: 0.35 * pop.value), blurRadius: 28, offset: const Offset(0, 12), spreadRadius: -6)],
                  ),
                  child: CustomPaint(painter: _CheckPainter(ring: ring.value, check: check.value)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          Opacity(
            opacity: text.value,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - text.value)),
              child: Column(children: [
                Text("You're in", style: TextStyle(color: ui.ink, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
                const SizedBox(height: 6),
                Text('Connected to ${widget.host}', style: TextStyle(color: ui.ink2, fontSize: 14.5)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double ring, check;
  _CheckPainter({required this.ring, required this.check});
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2 - 7;
    final p = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * ring, false, p..color = Colors.white.withValues(alpha: 0.55));
    if (check <= 0) return;
    final a = Offset(size.width * 0.30, size.height * 0.52), b = Offset(size.width * 0.44, size.height * 0.65), d = Offset(size.width * 0.70, size.height * 0.38);
    final path = Path()..moveTo(a.dx, a.dy);
    final first = (a - b).distance, second = (d - b).distance, len = (first + second) * check;
    if (len <= first) {
      final t = len / first; path.lineTo(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    } else {
      final t = (len - first) / second; path..lineTo(b.dx, b.dy)..lineTo(b.dx + (d.dx - b.dx) * t, b.dy + (d.dy - b.dy) * t);
    }
    canvas.drawPath(path, p..color = Colors.white..strokeWidth = 5);
  }
  @override
  bool shouldRepaint(_CheckPainter old) => old.ring != ring || old.check != check;
}
